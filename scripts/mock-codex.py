#!/usr/bin/python3
"""Offline app-server fixture. No network, credentials, or model calls."""
import json
import os
import sys
import time
from pathlib import Path

home = Path(os.environ["CODEX_HOME"])
scenario_file = home / "scenario.json"
scenario = json.loads(scenario_file.read_text()) if scenario_file.exists() else {}
mode = scenario.get("mode", "normal")
log = home / "mock-requests.jsonl"


def emit(message):
    print(json.dumps(message), flush=True)


def response(message, result):
    emit({"id": message["id"], "result": result})


def notify(method, params):
    emit({"method": method, "params": params})


with log.open("a") as output:
    output.write(json.dumps({"environment": {
        "CODEX_HOME": str(home), "cwd": os.getcwd(), "arguments": sys.argv[1:],
        "hasAPIKey": any(os.environ.get(k) for k in ["OPENAI_API_KEY", "CODEX_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY"])
    }}) + "\n")

initialized = False
for line in sys.stdin:
    message = json.loads(line)
    with log.open("a") as output:
        output.write(json.dumps(message) + "\n")
    method = message.get("method")
    if method is None:  # client reply to a server-initiated request
        continue
    if method == "initialize":
        if mode == "hang-initialize":
            continue
        response(message, {"userAgent": "mock-codex"})
    elif method == "initialized":
        initialized = True
    elif not initialized:
        emit({"id": message["id"], "error": {"code": -32000, "message": "Not initialized"}})
    elif method == "account/read":
        if mode == "crash":
            sys.exit(7)
        if mode == "error":
            emit({"id": message["id"], "error": {"code": 401, "message": "Sign-in expired"}})
        elif mode == "signed-out":
            response(message, {"account": None, "requiresOpenaiAuth": True})
        elif mode == "api-key-account":
            response(message, {"account": {"type": "apiKey"}, "requiresOpenaiAuth": True})
        else:
            response(message, {"account": {"type": "chatgpt", "email": "fixture@example.test", "planType": "plus"}, "requiresOpenaiAuth": True})
    elif method == "account/login/start":
        url = "https://example.test/fake" if mode == "bad-login-url" else "https://auth.openai.com/authorize?fixture=1"
        response(message, {"type": "chatgpt", "loginId": "mock-login", "authUrl": url})
    elif method == "account/logout":
        response(message, {})
    elif method == "model/list":
        if message["params"].get("cursor"):
            response(message, {"data": [{"id": "second", "model": "fixture-default", "displayName": "Fixture default", "isDefault": True}], "nextCursor": None})
        else:
            response(message, {"data": [{"id": "first", "model": "fixture-model", "displayName": "Fixture model", "isDefault": False}, {"id": "hidden", "model": "hidden", "hidden": True}], "nextCursor": "page-2"})
    elif method == "thread/start":
        response(message, {"thread": {"id": "fixture-thread", "ephemeral": True}})
    elif method == "turn/start":
        response(message, {"turn": {"id": "fixture-turn", "status": "inProgress"}})
        meta = {"threadId": "fixture-thread", "turnId": "fixture-turn"}
        notify("turn/started", {"threadId": "fixture-thread", "turn": {"id": "fixture-turn"}})
        if mode == "approval":
            emit({"id": "server-tool-1", "method": "item/commandExecution/requestApproval", "params": meta})
            continue
        if mode == "hang-turn":
            notify("item/agentMessage/delta", dict(meta, itemId="message", delta="Partial"))
            continue
        # Wrong-thread and wrong-turn deltas must not reach the conversation.
        notify("item/agentMessage/delta", dict(meta, threadId="unrelated", itemId="other", delta="LEAK"))
        notify("item/agentMessage/delta", dict(meta, turnId="unrelated", itemId="other", delta="LEAK"))
        if mode != "fallback":
            notify("item/agentMessage/delta", dict(meta, itemId="message", delta="Hello "))
            notify("item/agentMessage/delta", dict(meta, itemId="message", delta="world"))
        notify("item/completed", dict(meta, item={"id": "message", "type": "agentMessage", "text": "Hello world"}))
        status = "failed" if mode == "failed" else "interrupted" if mode == "interrupted" else "completed"
        turn = {"id": "fixture-turn", "status": status}
        if status == "failed":
            turn["error"] = {"message": "Fixture usage limit reached"}
        notify("turn/completed", {"threadId": "fixture-thread", "turn": turn})
    elif method in ["thread/unsubscribe", "turn/interrupt"]:
        response(message, {})
    else:
        emit({"id": message["id"], "error": {"code": -32601, "message": "Unknown method"}})
