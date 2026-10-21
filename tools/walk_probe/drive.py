"""Walking-cat probe driver. Usage: py -I drive.py <step> [args]
Steps:
  cmd "<line>"           send a probe command (auto seq), wait, print new log lines
  log [n]                print last n log lines
  patch                  add the test rows (AnimGameObject/Action/Interaction/InteractionBag)
  shot <name>            screenshot (no UI) into this folder, wait until written
"""
import json, os, sys, time, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
URL = "http://localhost:11212/mcp"
HERE = os.path.dirname(os.path.abspath(__file__))
MOD = "PawWalkProbe"
LOG = r"C:\Users\user\Documents\inZOI\Mods\InGame\PawWalkProbe\log\b1.cfg"
SEQ = os.path.join(HERE, "seq.txt")


def call(name, args):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                       "params": {"name": name, "arguments": args}}).encode("utf-8")
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read().decode("utf-8"))
    if "error" in resp:
        return "RPC ERROR " + json.dumps(resp["error"], ensure_ascii=False)
    res = resp["result"]
    text = "\n".join(c.get("text", "") for c in res.get("content", []))
    return ("TOOL ERROR " if res.get("isError") else "") + text


def loglines():
    try:
        with open(LOG, encoding="utf-8", errors="replace") as f:
            return f.read().split(" || ")
    except OSError:
        return []


def cmd(line, wait=1.5):
    seq = int(open(SEQ).read()) + 1 if os.path.exists(SEQ) else 100
    open(SEQ, "w").write(str(seq))
    before = loglines()
    print(call("uimod_cfg_save", {"mod_id": MOD, "Section": "cmd", "Key": "next", "Value": "%d;%s" % (seq, line)}))
    time.sleep(wait)
    after = loglines()
    new = after[len(before):] if after[:len(before)] == before else after[-5:]
    print("\n".join(new))


WALK = "/Game/Characters/Void/Void_Cat/Anim/ANIM_Void_Cat_Walk_F_Montage.ANIM_Void_Cat_Walk_F_Montage"
RUN = "/Game/Characters/Void/Void_Cat/Anim/ANIM_Void_Cat_Run_F_Montage.ANIM_Void_Cat_Run_F_Montage"


def rows():
    out = []
    for key, path, length in (("Walk", WALK, 1.6333333), ("Run", RUN, 0.6666667)):
        anim = "PawWalk_Cat" + key
        act = "PawWalk_" + key + "Act"
        inter = "PawWalk_" + key + "Test"
        out.append(("AnimGameObject", anim, {"ID": anim, "PlayingComponentName": "Root", "StartAnimSection": "Default",
            "AnimInfoList": [{"Gender": "Default", "AnimGrowthStep": "Default", "Animation": path,
                              "TotalPlayLength": length * 6, "LoopPlayLength": 0, "RateScale": 1, "RandomLoopAnims": []}]}))
        out.append(("Action", act, {"ID": act, "Actions": [
            {"BaseObject": "Target", "Command": "PlayVATAnim", "S1": anim, "S2": "None", "F1": 0, "F2": 0,
             "IsWaitFinishAction": False, "IsForceCancelable": True, "bEnableInsertAutoMove": True},
            {"BaseObject": "Self", "Command": "PlayAnim", "S1": "Character_VoidCat_Tickle", "S2": "None", "F1": 0, "F2": 0,
             "IsWaitFinishAction": True, "IsForceCancelable": True, "bEnableInsertAutoMove": True}]}))
        out.append(("Interaction", inter, {"ID": inter, "ActionIdList": [act], "InteractionSlotUsage": "Single",
                                           "PostureId": ["Stand"], "BodyParts": ["BothHands"]}))
        out.append(("InteractionBag", inter, {"ID": inter, "PostureGroupId": "StandGroup", "AgingConditionFlags": 504,
            "RepeatCount": 1, "InteractionSequence": [{"Probability": 1, "InteractionInfos": [{"InteractionId": inter, "Label": "A"}]}]}))
    return out


def patch():
    for alias, rid, row in rows():
        print(alias, rid, call("data_patch", {"method": "Append", "query": alias, "value": json.dumps(row)})[:300])
        print("  get:", call("data_table_get", {"alias": alias, "row": rid})[:400])


def shot(name):
    path = os.path.join(HERE, name).replace("\\", "/")
    print(call("screenshot_capture", {"Filename": path, "show_ui": False})[:200])
    for _ in range(20):
        time.sleep(0.5)
        r = call("screenshot_get_last", {})
        if '"saved":true' in r.replace(" ", ""):
            print("saved", path)
            return
    print("not saved yet")


if __name__ == "__main__":
    step = sys.argv[1]
    if step == "cmd":
        cmd(sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 1.5)
    elif step == "log":
        print("\n".join(loglines()[-int(sys.argv[2] if len(sys.argv) > 2 else 10):]))
    elif step == "patch":
        patch()
    elif step == "names":
        eid = sys.argv[2]
        for n in sys.argv[3:]:
            cmd("anim %s %s" % (eid, n), 1.2)
    elif step == "loads":
        for p in sys.argv[2:]:
            cmd("load " + p, 1.8)
    elif step == "shot":
        shot(sys.argv[2])
