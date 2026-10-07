"""Run the Counter script workflow against temporary Anvil nodes (Python stdlib only)."""

import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    processes = []
    with tempfile.TemporaryDirectory(prefix="erc1155-proxy-lab-") as temporary:
        env = dict(os.environ, ANVIL="", FOUNDRY_BROADCAST=f"{temporary}/broadcast")
        mnemonic = "test test test test test test test test test test test junk"

        def command(*args):
            result = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True, timeout=90)
            if result.returncode:
                raise AssertionError(f"{args[0]} failed:\n{result.stdout}\n{result.stderr}")
            return result.stdout.strip()

        def rpc(url, method, params=None):
            payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or []}).encode()
            request = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(request, timeout=2) as response:
                data = json.load(response)
            assert "error" not in data, data.get("error")
            return data["result"]

        def start_node(*args):
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            url = f"http://127.0.0.1:{port}"
            process = subprocess.Popen(
                ["anvil", "--host", "127.0.0.1", "--port", str(port), "--mnemonic", mnemonic,
                 "--cache-path", f"{temporary}/anvil-{port}", *args],
                cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            processes.append(process)
            for _ in range(100):
                assert process.poll() is None, "Anvil exited before becoming ready"
                try:
                    rpc(url, "eth_chainId")
                    return url
                except OSError:
                    time.sleep(0.1)
            raise AssertionError("Anvil did not become ready")

        def script(url, signature="run()", *options):
            return command("forge", "script", "script/Counter.s.sol:CounterScript", "--sig", signature,
                           "--rpc-url", url, "-vvvv", *options)

        def number(url, block="latest"):
            return int(rpc(url, "eth_call", [{"to": env["COUNTER_ADDRESS"], "data": "0x8381f58a"}, block]), 16)

        try:
            env["PRIVATE_KEY"] = command("cast", "wallet", "private-key", "--mnemonic", mnemonic)
            source = start_node()
            env["ANVIL"] = source
            initial_block = rpc(source, "eth_blockNumber")
            assert "number: 1" in script("anvil", "deploy()")
            assert rpc(source, "eth_blockNumber") == initial_block
            script("anvil", "deploy()", "--broadcast", "--slow")
            artifacts = list(Path(temporary, "broadcast/Counter.s.sol/31337").glob("*-latest.json"))
            assert len(artifacts) == 1, [str(path) for path in Path(temporary).rglob("*.json")]
            artifact = json.loads(artifacts[0].read_text())
            env["COUNTER_ADDRESS"] = artifact["transactions"][0]["contractAddress"]
            deployment_block = artifact["receipts"][0]["blockNumber"]
            assert number(source, deployment_block) == 0
            assert number(source) == 1
            first_increment_block = rpc(source, "eth_blockNumber")
            script(source, "increment()", "--broadcast")
            assert number(source) == 2
            block_before = rpc(source, "eth_blockNumber")
            assert "number: 3" in script(source, "increment()")
            assert number(source) == 2
            assert rpc(source, "eth_blockNumber") == block_before
            assert "number: 2" in script("anvil")
            assert command("cast", "call", env["COUNTER_ADDRESS"], "number()(uint256)", "--rpc-url", source) == "2"
            assert int(command("cast", "block-number", "--rpc-url", source)) == int(block_before, 16)
            assert "number: 0" in script(source, "run()", "--fork-block-number", str(int(deployment_block, 16)))
            assert "number: 1" in script(source, "run()", "--fork-block-number", str(int(first_increment_block, 16)))
            assert number(source) == 2
            fork = start_node("--no-storage-caching", "--fork-url", source, "--fork-block-number", str(int(deployment_block, 16)))
            assert number(fork) == 0
            script(fork, "increment()", "--broadcast")
            assert number(fork) == 1
            assert number(source) == 2
            env["PRIVATE_KEY"] = ""
            assert "number: 2" in script("anvil")
            print("PASS: deploy, broadcast, dry run, historical read, and isolated Anvil fork")
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
            print("Temporary Anvil nodes stopped")


if __name__ == "__main__":
    main()
