class_name Applicant
extends Resource
## 一位登記者：鬼、活人、假冒鬼的活人、或抽查員。
## 真相（kind）只有系統知道；玩家靠文件、畫面、問答推。

enum Kind { GHOST, HUMAN, HUMAN_DISGUISED, INSPECTOR }

@export var id: String = ""
@export var display_name: String = ""          # 文件上的名字（可能是假的）
@export var kind: Kind = Kind.GHOST
@export var is_story: bool = false              # 故事鬼：有執念軸、固定出現
@export var story_floor_hint: int = -1          # 故事鬼原本住的樓層（A1 設計表用）
@export var initial_axis: int = 0

# ── 身分資料（文件會引用這些，真假由文件自己決定）──
@export var zodiac: String = ""                 # 鼠牛虎兔龍蛇馬羊猴雞狗豬
@export var death_date: String = ""             # YYYY-MM-DD，活人為空
@export var death_place: String = ""
@export var death_cause: String = ""
@export var address: String = ""
@export var age: int = 0

# ── 文件 ──
@export var documents: Array[Document] = []

# ── 畫面線索（部件 id；影子/腳是判定用的旗標）──
@export var portrait: Dictionary = {}           # {face, hair, outfit, trait}
@export var has_shadow: bool = false            # 活人才有影子
@export var feet_on_ground: bool = false        # 活人腳著地
@export var visual_tells: Array[String] = []    # 其他畫面破綻 tag

# ── 問答 ──
@export var answers: Dictionary = {}            # question_id -> {text, contradicts: [doc_id.field]}

# ── 關係（排房推理的真相）──
@export var relations: Array[Dictionary] = []   # [{with: id, kind: hostile|family|debt|property, clue: "..."}]

# ── 對話樹 ──
## dialogue = {"start": node_id, "nodes": {id: {"line": "對方說的話", "options": [
##   {"text": "你的回應", "next": node_id 或 "", "tone": "kind|neutral|harsh",
##    "contradicts": ["doc_id.欄位"], "effects": [{"kind": "axis", "value": 5}], "note": "筆記本一句話"}]}}}
## 沒寫的登記者會由 DataLoader 依 answers 自動合成一棵基本樹。
@export var dialogue: Dictionary = {}
@export var temper: int = 0                     # 本次對話累積的不耐（harsh +1 / kind −1），結算用

# ── 文本 ──
@export var intro_line: String = ""             # 走到櫃檯時說的第一句
@export var plea_line: String = ""              # 被拒絕時說的話（活人的道德壓力）
@export var on_approve: String = ""             # 蓋准予入住後的反應
@export var on_deny: String = ""                # 蓋拒絕後的反應（空則用 plea_line）
@export var on_report: String = ""              # 被通報時的反應
@export var return_as: String = ""              # 活人被放進來後，隔晚回來時變成哪個 applicant id


func is_ghost() -> bool:
	return kind == Kind.GHOST


func should_be_admitted() -> bool:
	return kind == Kind.GHOST


func document(doc_id: String) -> Document:
	for d in documents:
		if d.id == doc_id:
			return d
	return null


func has_dialogue() -> bool:
	return dialogue.has("start") and dialogue.has("nodes")


func dialogue_node(id: String) -> Dictionary:
	return (dialogue.get("nodes", {}) as Dictionary).get(id, {})


## 對話樹裡是否有任何「說了會跟文件矛盾」的選項（給 Judge 的 answer_contradiction 用）
func dialogue_has_contradiction() -> bool:
	for n in (dialogue.get("nodes", {}) as Dictionary).values():
		for o in n.get("options", []):
			if not (o.get("contradicts", []) as Array).is_empty():
				return true
		if not (n.get("contradicts", []) as Array).is_empty():
			return true
	return false


func relation_with(other_id: String) -> Dictionary:
	for r in relations:
		if r.get("with", "") == other_id:
			return r
	return {}


static func kind_from_string(s: String) -> Kind:
	match s:
		"human": return Kind.HUMAN
		"human_disguised": return Kind.HUMAN_DISGUISED
		"inspector": return Kind.INSPECTOR
		_: return Kind.GHOST


static func from_dict(d: Dictionary) -> Applicant:
	var a := Applicant.new()
	a.id = d.get("id", "")
	a.display_name = d.get("name", "")
	a.kind = kind_from_string(d.get("kind", "ghost"))
	a.is_story = d.get("is_story", false)
	a.story_floor_hint = int(d.get("story_floor_hint", -1))
	a.initial_axis = int(d.get("initial_axis", 0))
	a.zodiac = d.get("zodiac", "")
	a.death_date = d.get("death_date", "")
	a.death_place = d.get("death_place", "")
	a.death_cause = d.get("death_cause", "")
	a.address = d.get("address", "")
	a.age = int(d.get("age", 0))
	for doc in d.get("documents", []):
		a.documents.append(Document.from_dict(doc))
	a.portrait = d.get("portrait", {})
	a.has_shadow = d.get("has_shadow", false)
	a.feet_on_ground = d.get("feet_on_ground", false)
	a.visual_tells.assign(d.get("visual_tells", []))
	a.answers = d.get("answers", {})
	a.relations.assign(d.get("relations", []))
	a.intro_line = d.get("intro_line", "")
	a.plea_line = d.get("plea_line", "")
	a.on_approve = d.get("on_approve", "")
	a.on_deny = d.get("on_deny", "")
	a.on_report = d.get("on_report", "")
	a.dialogue = d.get("dialogue", {})
	a.return_as = d.get("return_as", "")
	return a
