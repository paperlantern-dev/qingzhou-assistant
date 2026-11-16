#!/bin/bash
# End-to-end tests of sending, with the real app driving 模拟微信 (the mock chat app).
# Each case starts both apps, lets one customer write, and then checks the mock's own record of
# what was really sent and what is in each chat's input box.
#   scripts/e2e_send_safety.sh [case name ...]      (no names = all cases)
# Needs the Screen Recording and Accessibility permissions for build/轻舟助手.app, and nobody using
# the mouse or keyboard while it runs (about 6 minutes). Test runs keep their data in a temporary
# folder and never touch the owner's customer records.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${E2E_OUT:-$(mktemp -d)}"
PORT=8765
WANG="客户·王女士"; LI="客户·李先生"
APP="build/轻舟助手.app/Contents/MacOS/QingzhouApp"; MOCK="build/模拟微信.app"
[ -x "$APP" ] && [ -d "$MOCK" ] || bash scripts/build_app.sh >/dev/null
python3 scripts/fake_model.py "$PORT" & MODEL=$!
stop_apps() { pkill -f "模拟微信.app/Contents/MacOS" 2>/dev/null; pkill -f "轻舟助手.app/Contents/MacOS/QingzhouApp" 2>/dev/null; sleep 1; }
trap 'stop_apps; kill $MODEL 2>/dev/null' EXIT

# run <name> <seconds> "<mock args>" "<app args>" "<python check on d (the mock's record) and log (the app's log)>"
FAILED=0
run() {
  local name="$1" secs="$2" mock_args="$3" app_args="$4" check="$5" dir="$OUT/$1"
  if [ -n "$ONLY" ] && ! echo " $ONLY " | grep -q " $name "; then return; fi
  mkdir -p "$dir"; stop_apps
  eval "open -n \"$MOCK\" --args --log \"$dir/mock.json\" $mock_args"
  sleep 2
  eval "\"$APP\" --autotest \"$dir/report.json\" --duration $secs --data-dir \"$dir/data\" --kb \"$PWD/test-fixtures/shop-knowledge\" \
        --api-base http://127.0.0.1:$PORT/v1 --api-model test $app_args" >"$dir/app.out" 2>&1 &
  sleep $((secs + 4)); stop_apps
  if python3 - "$dir" "$check" <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + "/mock.json"))
log = "\n".join(e["text"] for e in json.load(open(sys.argv[1] + "/report.json"))["log"])
TOKEN = "自动测试回复"
def mine(chat):      # my messages in that chat, as the mock recorded them
    return [m["text"] for c in d["contacts"] if c["id"] == chat for m in c["messages"] if m["fromMe"]][1:]
def sent(chat): return sum(TOKEN in t for t in mine(chat))
def pictures(chat): return sum(t.startswith("[图片]") for t in mine(chat))
def box(chat): return d["drafts"].get(chat, "")
ok = eval(sys.argv[2])
if not ok:
    print("   sent:", {c["id"]: mine(c["id"]) for c in d["contacts"]}, "\n   boxes:", d["drafts"], "\n   log tail:", log[-600:])
sys.exit(0 if ok else 1)
PY
  then echo "PASS  $name"; else echo "FAIL  $name   (see $dir)"; FAILED=$((FAILED + 1)); fi
}
ONLY="$*"
ASK="--say $WANG 脐橙怎么卖"

# The tests can tell a send from no send.
run control-background 30 "$ASK" "" \
  'sent("客户·王女士") == 1 and sent("客户·李先生") == 0 and box("客户·王女士") == ""'
run control-foreground 30 "$ASK" "--foreground" \
  'sent("客户·王女士") == 1 and sent("客户·李先生") == 0'

# Another chat is opened after the reply is typed, before Return: nothing is sent to anyone, and
# nothing is deleted in the chat now showing.
run switch-background 35 "$ASK --when-typed switch:$LI --draft $LI 李先生这边我自己写的" "--hold-before-send 4" \
  'sent("客户·李先生") == 0 and sent("客户·王女士") == 0 and box("客户·李先生") == "李先生这边我自己写的" and "当前会话已经换了" in log'
run switch-foreground 35 "$ASK --when-typed switch:$LI --draft $LI 李先生这边我自己写的" "--foreground --hold-before-send 4" \
  'sent("客户·李先生") == 0 and sent("客户·王女士") == 0 and box("客户·李先生") == "李先生这边我自己写的" and "当前会话已经换了" in log'

# The customer writes again before Return: the old reply is taken back, and one new reply goes out.
run newer-message-background 55 "$ASK --when-typed receive:$WANG:再加一箱苹果" "--hold-before-send 4" \
  'sent("客户·王女士") == 1 and box("客户·王女士") == "" and "对方又发了新消息" in log'
run newer-message-foreground 55 "$ASK --when-typed receive:$WANG:再加一箱苹果" "--foreground --hold-before-send 4" \
  'sent("客户·王女士") == 1 and box("客户·王女士") == "" and "对方又发了新消息" in log'

# Paused right before Return: nothing is sent, and the reply is taken back out of the box.
run pause-background 30 "$ASK" "--hold-before-send 3 --pause-in-hold" \
  'sent("客户·王女士") == 0 and box("客户·王女士") == "" and "已暂停" in log'
run pause-foreground 30 "$ASK" "--foreground --hold-before-send 3 --pause-in-hold" \
  'sent("客户·王女士") == 0 and box("客户·王女士") == ""'

# The owner left words of their own in the input box: nothing is sent, and their words are untouched.
run owner-draft-background 30 "$ASK --draft $WANG 我自己打到一半的话" "" \
  'sent("客户·王女士") == 0 and box("客户·王女士") == "我自己打到一半的话"'
run owner-draft-foreground 30 "$ASK --draft $WANG 我自己打到一半的话" "--foreground" \
  'sent("客户·王女士") == 0 and box("客户·王女士") == "我自己打到一半的话"'

# 我确认后发: an approved draft meets the same checks.
run approved-draft-sent 40 "$ASK" "--assist --approve-after 1" \
  'sent("客户·王女士") == 1 and sent("客户·李先生") == 0'
run approved-draft-switch 40 "$ASK --when-typed switch:$LI" "--assist --approve-after 1 --hold-before-send 4" \
  'sent("客户·李先生") == 0 and sent("客户·王女士") == 0 and "当前会话已经换了" in log'

# A picture (关键词触发): sent normally, and held back when the chat changes after it is pasted.
PIC="--trigger-image 怎么卖 $PWD/test-fixtures/images/product.png"
run picture-sent 35 "$ASK" "$PIC" \
  'pictures("客户·王女士") == 1 and pictures("客户·李先生") == 0'
run picture-switch 35 "$ASK --when-typed switch:$LI" "$PIC --hold-before-send 4" \
  'pictures("客户·李先生") == 0 and pictures("客户·王女士") == 0 and "当前会话已经换了" in log'

echo "Reports: $OUT"
if [ "$FAILED" != "0" ]; then echo "$FAILED case(s) failed."; exit 1; fi
echo "All sending-safety cases passed."
