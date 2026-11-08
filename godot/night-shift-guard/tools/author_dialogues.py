#!/usr/bin/env python3
"""
手寫對話樹寫進 data/applicants.json（重點角色）。
其他登記者沒有 dialogue 欄位，執行期由 DataLoader.synthesize_dialogue 自動合成。

用法：python3 tools/author_dialogues.py
之後若要改對話，直接改 applicants.json 也可以；這支只是方便一次大量寫入。
"""
import io
import json
from pathlib import Path

P = Path(__file__).resolve().parent.parent / "data" / "applicants.json"
apps = json.load(io.open(P, encoding="utf-8"))
byid = {a["id"]: a for a in apps}

D = {}

D["chen_bo"] = {
    "on_approve": "……好。我在房間等。他來了你一定要叫我。",
    "on_deny": "那我在外面車上等就好。他來了麻煩跟他說一聲。",
    "dialogue": {"start": "s", "nodes": {
        "s": {"line": "不好意思，我兒子有沒有來過？姓陳，開一台白色的車。", "options": [
            {"text": "「還沒有。您先登記，我幫您留意。」", "next": "n1", "tone": "kind"},
            {"text": "「這裡不接受訪客。請出示文件。」", "next": "n1b", "tone": "harsh"},
            {"text": "「您兒子叫什麼名字？」", "next": "n2", "tone": "neutral"}]},
        "n1": {"line": "好、好。他說九月三號要來接我。今天幾號？", "options": [
            {"text": "「九月三號已經過了，陳伯。」", "next": "n3", "tone": "neutral", "note": "陳伯一直在等九月三號"},
            {"text": "「快到了，您再等一下。」", "next": "n4", "tone": "kind", "effects": [{"kind": "axis", "value": 5}]}]},
        "n1b": {"line": "……對不起。我不是來找麻煩的。我只是在等人。", "options": [
            {"text": "「您兒子叫什麼名字？」", "next": "n2", "tone": "neutral"},
            {"text": "「文件。」", "next": "", "tone": "harsh"}]},
        "n2": {"line": "志豪。林志豪。……跟他媽媽姓。他媽媽後來改嫁了，住七樓那家。", "options": [
            {"text": "「七樓那家——二十年前失火那家？」", "next": "n5", "tone": "neutral", "note": "陳伯的兒子志豪住在 7F 林家"},
            {"text": "「好，我記下來了。」", "next": "n3", "tone": "neutral"}]},
        "n3": {"line": "……你是不是知道什麼？你那個眼神。", "options": [
            {"text": "「我什麼都不知道。您先登記。」", "next": "", "tone": "neutral"},
            {"text": "「陳伯，他不會來了。」", "next": "n6", "tone": "neutral", "effects": [{"kind": "axis", "value": -20}], "note": "跟陳伯說了真話"}]},
        "n4": {"line": "對、對，快到了。他很孝順的。每次都說快到了。", "options": [
            {"text": "「……」", "next": "", "tone": "neutral"}]},
        "n5": {"line": "（他沒有回答。車鑰匙在他手裡轉了一圈。）\n……他說過要來接我。他答應過。", "options": [
            {"text": "「我幫您登記。有消息我會告訴您。」", "next": "", "tone": "kind"},
            {"text": "「陳伯，他不會來了。」", "next": "n6", "tone": "neutral", "effects": [{"kind": "axis", "value": -20}], "note": "跟陳伯說了真話"}]},
        "n6": {"line": "（他看著你很久。停車場那頭，一台車的大燈亮了又熄。）\n……我知道。我一直都知道。只是沒有人敢跟我說。", "options": [
            {"text": "「我幫您登記。先休息吧。」", "next": "", "tone": "kind", "effects": [{"kind": "axis", "value": -10}]}]},
    }},
}

D["a_mei"] = {
    "on_approve": "叔叔，你不要關燈喔。媽媽來了要看得到我。",
    "on_deny": "……那我在樓下等。你不要關燈喔。",
    "dialogue": {"start": "s", "nodes": {
        "s": {"line": "叔叔，媽媽有沒有來？她說等一下就回來。", "options": [
            {"text": "「還沒有。妳一個人嗎？」", "next": "n1", "tone": "kind"},
            {"text": "「小朋友，這裡不能玩。妳的證件呢？」", "next": "n1b", "tone": "harsh"},
            {"text": "「妳媽媽叫什麼名字？」", "next": "n2", "tone": "neutral"}]},
        "n1": {"line": "嗯。媽媽叫我在林阿姨家等。可是後來好熱，大家都在睡覺，我叫不醒他們。", "options": [
            {"text": "「林阿姨家……在七樓？」", "next": "n3", "tone": "neutral", "note": "阿妹那晚在 7F 林家過夜"},
            {"text": "「沒事了，現在不熱了。」", "next": "n4", "tone": "kind", "effects": [{"kind": "axis", "value": -10}]}]},
        "n1b": {"line": "（她看著地板。）……媽媽說不可以跟兇的人講話。", "options": [
            {"text": "「對不起。叔叔太累了。妳媽媽叫什麼名字？」", "next": "n2", "tone": "kind"},
            {"text": "「文件拿出來。」", "next": "", "tone": "harsh"}]},
        "n2": {"line": "林淑芬。她在十二樓等我。她說星期六要帶我去玩。", "options": [
            {"text": "「今天就是星期六。」", "next": "n4", "tone": "kind", "effects": [{"kind": "axis", "value": -5}]},
            {"text": "「十二樓……跟妳死亡證明上的七樓不一樣。」", "next": "n3", "tone": "neutral", "note": "住址 12F、死在 7F"}]},
        "n3": {"line": "……我不是故意要去七樓的。媽媽說林阿姨會照顧我。\n叔叔，你要不要一起玩？", "options": [
            {"text": "「明天。」", "next": "n5", "tone": "neutral"},
            {"text": "「好啊。」", "next": "n6", "tone": "kind", "effects": [{"kind": "axis", "value": 15}], "note": "答應阿妹『一起玩』——她記住了"},
            {"text": "「不要。」", "next": "n6b", "tone": "harsh"}]},
        "n4": {"line": "（她笑了。走廊盡頭的燈亮了一盞。）\n叔叔，你要不要一起玩？", "options": [
            {"text": "「明天。」", "next": "n5", "tone": "neutral"},
            {"text": "「好啊。」", "next": "n6", "tone": "kind", "effects": [{"kind": "axis", "value": 15}], "note": "答應阿妹『一起玩』——她記住了"}]},
        "n5": {"line": "每個人都說明天。……好吧。明天。", "options": [{"text": "「我幫妳登記。」", "next": "", "tone": "neutral"}]},
        "n6": {"line": "真的？你答應了喔。你答應了就不可以反悔。\n（你的桌上多了一顆彈珠。）", "options": [{"text": "「……我幫妳登記。」", "next": "", "tone": "neutral"}]},
        "n6b": {"line": "（她沒有哭。她只是站著，然後所有的燈暗了一秒。）", "options": [{"text": "「文件。」", "next": "", "tone": "neutral"}]},
    }},
}

D["lin_son"] = {
    "on_approve": "……謝謝。如果他問起我，跟他說我有想過要去接他。",
    "on_deny": "也好。我本來就不該跟他們一起吃那頓飯。",
    "dialogue": {"start": "s", "nodes": {
        "s": {"line": "我可以不跟他們住同一層嗎？", "options": [
            {"text": "「他們是誰？」", "next": "n1", "tone": "neutral"},
            {"text": "「房間我來安排。先看文件。」", "next": "n2", "tone": "neutral"},
            {"text": "「你說了算嗎？」", "next": "n1b", "tone": "harsh"}]},
        "n1": {"line": "七樓那家。我媽改嫁的那家。……他們一直在等一頓團圓飯，但那天我根本不想在。", "options": [
            {"text": "「那天你本來要去哪？」", "next": "n3", "tone": "kind"},
            {"text": "「所以你是林家的兒子？」", "next": "n2", "tone": "neutral"}]},
        "n1b": {"line": "……不是。什麼都不是我說了算。那天也是。", "options": [
            {"text": "「那天你本來要去哪？」", "next": "n3", "tone": "kind"},
            {"text": "「文件。」", "next": "", "tone": "neutral"}]},
        "n2": {"line": "身分證背面你自己看。父親那欄不是姓林。", "options": [
            {"text": "「陳文雄。……停車場那位？」", "next": "n3", "tone": "neutral", "note": "林志豪的生父是 B1 陳文雄"},
            {"text": "「好，我看一下。」", "next": "", "tone": "neutral"}]},
        "n3": {"line": "九月三號。我答應我爸——親生的那個——要去停車場接他回家。我媽叫我先吃完飯再走。\n我沒有走成。", "options": [
            {"text": "「他還在等你。他每晚都問。」", "next": "n4", "tone": "kind", "effects": [{"kind": "axis", "value": -15}], "note": "志豪知道陳伯還在等"},
            {"text": "「二十年了，你們都還卡在這裡。」", "next": "n5", "tone": "neutral"}]},
        "n4": {"line": "（他很久沒有說話。）\n……可以讓我跟他同一層嗎？不要跟七樓的。跟他。", "options": [
            {"text": "「我安排。」", "next": "", "tone": "kind", "effects": [{"kind": "axis", "value": -10}]},
            {"text": "「我不能答應你。」", "next": "", "tone": "neutral", "effects": [{"kind": "axis", "value": 10}]}]},
        "n5": {"line": "你以為我們想？……算了。你安排吧。", "options": [{"text": "「文件。」", "next": "", "tone": "neutral"}]},
    }},
}

D["h_lost_student"] = {
    "on_approve": "太好了，謝謝！我只住一晚，明天一早就走。",
    "on_deny": "可是山下已經沒公車了……好吧。我……我在外面等天亮好了。",
    "dialogue": {"start": "s", "nodes": {
        "s": {"line": "不好意思，請問這裡是民宿嗎？我迷路了。", "options": [
            {"text": "「這裡不是民宿。妳怎麼上來的？」", "next": "n1", "tone": "neutral"},
            {"text": "「這裡不收活……不收散客。請下山。」", "next": "n1b", "tone": "harsh"},
            {"text": "「先進來坐，外面冷。」", "next": "n1c", "tone": "kind"}]},
        "n1": {"line": "Google Maps 導的。它說這裡有住宿……手機只剩 3%。請問有插座嗎？", "options": [
            {"text": "「妳知道今天幾號嗎？」", "next": "n2", "tone": "neutral"},
            {"text": "「這裡沒有插座。也沒有住宿。」", "next": "n3", "tone": "harsh"}]},
        "n1b": {"line": "可是……最後一班公車十點就走了。我真的不知道怎麼下去。", "options": [
            {"text": "「我幫妳叫車。在外面等。」", "next": "n3", "tone": "kind"},
            {"text": "「不關我的事。」", "next": "n3b", "tone": "harsh"}]},
        "n1c": {"line": "謝謝！（她走進來，日光燈下她的影子拉得很長。）請問廁所在哪？", "options": [
            {"text": "「……妳有影子。」", "next": "n2b", "tone": "neutral", "note": "活人有影子、會問廁所"},
            {"text": "「左邊走到底。」", "next": "n2", "tone": "kind"}]},
        "n2": {"line": "十一月八號，星期六啊。怎麼了？", "options": [
            {"text": "「妳身分證給我看一下。」", "next": "n3", "tone": "neutral", "contradicts": ["h_student_id.註銷"], "note": "知道今天幾號、身分證沒註銷——活人"},
            {"text": "「沒事。」", "next": "", "tone": "neutral"}]},
        "n2b": {"line": "啊？影子……每個人都有影子吧？你在說什麼？", "options": [
            {"text": "「這裡的客人沒有。」", "next": "n3", "tone": "neutral"},
            {"text": "「沒事，妳先坐。」", "next": "", "tone": "kind"}]},
        "n3": {"line": "（她把身分證推過來，手在抖。）你……你們這裡到底是什麼地方？", "options": [
            {"text": "「一個妳不該進來的地方。下山的路我畫給妳。」", "next": "", "tone": "kind"},
            {"text": "「看完文件我就告訴妳。」", "next": "", "tone": "neutral"}]},
        "n3b": {"line": "（她咬著嘴唇沒說話，背包的帶子被她抓得很緊。）", "options": [{"text": "「……」", "next": "", "tone": "neutral"}]},
    }},
}

D["h_grief_mother"] = {
    "on_approve": "謝謝你。謝謝你。小妹——媽媽來了——",
    "on_deny": "我知道我還活著。我就是想跟她說對不起。……你能幫我轉達嗎？",
    "dialogue": {"start": "s", "nodes": {
        "s": {"line": "我女兒是不是在這裡？拜託你讓我見她一面就好。", "options": [
            {"text": "「您女兒叫什麼名字？」", "next": "n1", "tone": "neutral"},
            {"text": "「這裡不是探視的地方。請回。」", "next": "n1b", "tone": "harsh"},
            {"text": "「您先坐。慢慢說。」", "next": "n1c", "tone": "kind"}]},
        "n1": {"line": "林小妹。八歲。穿紅色洋裝。二十年前……我把她放在朋友家一晚，就一晚。", "options": [
            {"text": "「七樓林家那場火。」", "next": "n2", "tone": "neutral", "note": "林淑芬是阿妹的媽媽，把她寄放在林家那晚失火"},
            {"text": "「我不能透露住客資料。」", "next": "n3", "tone": "neutral"}]},
        "n1b": {"line": "我等了二十年！我每天都來廟裡問！土地公不回答我，你也不回答我！", "options": [
            {"text": "「……您先坐。」", "next": "n1c", "tone": "kind"},
            {"text": "「再吵我叫人。」", "next": "n3b", "tone": "harsh"}]},
        "n1c": {"line": "（她坐下，手裡的照片已經磨到看不清。）有人說，死的人會先來這裡。所以我來了。我帶了她的訃聞，證明我是她媽媽。", "options": [
            {"text": "「您知道自己還活著吧。」", "next": "n2", "tone": "neutral"},
            {"text": "「我看一下訃聞。」", "next": "", "tone": "neutral"}]},
        "n2": {"line": "我知道。我知道。我就是……想跟她說對不起。說我不是故意不回來的。\n你讓我進去一晚，一晚就好。我不怕出不來。", "options": [
            {"text": "「我不能。但如果她來了，我會轉達。」", "next": "n4", "tone": "kind", "note": "答應替林淑芬轉達"},
            {"text": "「進去了妳就是下一個登記的。」", "next": "n4", "tone": "neutral"},
            {"text": "「好吧。」", "next": "", "tone": "kind"}]},
        "n3": {"line": "……你跟其他人一樣。好。那我在外面等。我每晚都會來。", "options": [{"text": "「……」", "next": "", "tone": "neutral"}]},
        "n3b": {"line": "（她站起來，又坐下。）對不起。對不起。我只是——", "options": [{"text": "「您女兒叫什麼名字？」", "next": "n1", "tone": "kind"}]},
        "n4": {"line": "（她把照片推過來。）那你告訴她：媽媽星期六有來。每個星期六都有來。", "options": [
            {"text": "「我會的。」", "next": "", "tone": "kind", "effects": [{"kind": "flag", "key": "promised_a_mei_mother", "value": True}]}]},
    }},
}

D["h_debt_runner"] = {
    "on_approve": "（他笑了。）算你識相。",
    "on_deny": "你要我怎麼證明？切一塊給你看？……操。",
    "on_report": "你他媽——你知道我是誰嗎？放開我！我有死亡證明！",
    "dialogue": {"start": "s", "nodes": {
        "s": {"line": "我死了，這是證明。給我房間。", "options": [
            {"text": "「請問怎麼走的？」", "next": "n1", "tone": "neutral"},
            {"text": "「死亡證明我看一下。醫院是哪一家？」", "next": "n2", "tone": "neutral"},
            {"text": "「這麼急？死人不趕時間。」", "next": "n1b", "tone": "harsh"}]},
        "n1": {"line": "車禍。林丘區。十一月五號。都寫在上面了，你自己看。", "options": [
            {"text": "「幾點？」", "next": "n3", "tone": "neutral"},
            {"text": "「節哀。」", "next": "n4", "tone": "kind"}]},
        "n1b": {"line": "（他盯著你。）你最好小心一點講話。我活著的時候認識很多人。", "options": [
            {"text": "「活著的時候。」", "next": "n2", "tone": "neutral"},
            {"text": "「文件。」", "next": "", "tone": "neutral"}]},
        "n2": {"line": "長安紀念醫院。章在上面。", "options": [
            {"text": "「這個章是殯葬業者的，不是醫院的。」", "next": "n5", "tone": "neutral", "contradicts": ["h_runner_death.開立醫院"], "note": "死亡證明的章是殯葬業者——偽造"},
            {"text": "「好。」", "next": "", "tone": "neutral"}]},
        "n3": {"line": "晚上十點。……大概。誰會記得自己幾點死的？", "options": [
            {"text": "「這裡的客人都記得。」", "next": "n5", "tone": "neutral", "contradicts": ["h_runner_death.死亡時間"], "note": "對自己的死亡時間含糊——活人"},
            {"text": "「也是。」", "next": "", "tone": "neutral"}]},
        "n4": {"line": "……哈。對，節哀。你人不錯。所以房間呢？", "options": [
            {"text": "「我再看一下文件。」", "next": "n2", "tone": "neutral"},
            {"text": "「馬上。」", "next": "", "tone": "kind"}]},
        "n5": {"line": "（他的手伸進外套。然後停住。）\n……聽著。有人要我的命。真的要。我只要躲三天。三天就好。你讓我進去，我出去之後有你的好處。", "options": [
            {"text": "「這裡進去就出不來了。你確定？」", "next": "n6", "tone": "neutral"},
            {"text": "「出去。」", "next": "", "tone": "harsh"},
            {"text": "「……三天。」", "next": "", "tone": "kind"}]},
        "n6": {"line": "（他沒有回答。他看了一眼門外的黑，然後看著你。）\n比外面好。", "options": [{"text": "「……」", "next": "", "tone": "neutral"}]},
    }},
}

for aid, patch in D.items():
    byid[aid].update(patch)
    # 驗證每個 next 都存在
    nodes = patch["dialogue"]["nodes"]
    for nid, n in nodes.items():
        for o in n.get("options", []):
            nxt = o.get("next", "")
            assert nxt == "" or nxt in nodes, f"{aid}.{nid} → {nxt} 不存在"

io.open(P, "w", encoding="utf-8").write(json.dumps(apps, ensure_ascii=False, indent=2) + "\n")
print(f"寫入 {len(D)} 位手寫對話")
