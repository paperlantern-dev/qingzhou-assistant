#!/usr/bin/env python3
"""A stand-in for the model during tests: answers every chat request with the same reply.
   fake_model.py <port>"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REPLY = "类型：问题\n引用：1\n回复：自动测试回复，脐橙五斤装二十九元"

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"choices": [{"message": {"role": "assistant", "content": REPLY}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
