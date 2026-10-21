nodes = []
def node(name, typ, parent=None, props=None):
    head = f'[node name="{name}" type="{typ}"' + (f' parent="{parent}"' if parent is not None else '') + ']'
    body = '\n'.join(f'{k} = {v}' for k, v in (props or {}).items())
    nodes.append(head + ('\n' + body if body else ''))
FULL = {"layout_mode": 1, "anchors_preset": 15, "anchor_right": 1.0, "anchor_bottom": 1.0, "grow_horizontal": 2, "grow_vertical": 2}
C = {"layout_mode": 2}
def btn(name, parent, text, minsize="Vector2(0, 44)", extra=None):
    p = {"custom_minimum_size": minsize, "layout_mode": 2, "text": f'"{text}"'}
    p.update(extra or {}); node(name, "Button", parent, p)
def label(name, parent, text, extra=None):
    p = {"layout_mode": 2, "text": f'"{text}"'}
    p.update(extra or {}); node(name, "Label", parent, p)
def rich(name, parent, extra=None):
    p = {"layout_mode": 2, "size_flags_horizontal": 3, "bbcode_enabled": "true", "fit_content": "true", "scroll_active": "false"}
    p.update(extra or {}); node(name, "RichTextLabel", parent, p)
GOLD = "Color(1, 0.82, 0.3, 1)"
LEFT_W = 230
RIGHT_W = 150
# V0.4：版面高度（棋盤可用的垂直空間＝畫面高度扣掉上下兩條）
TOP_H = 44
BOTTOM_H = 126
SIDE_TOP = TOP_H + 4
SIDE_BOTTOM = -(BOTTOM_H + 4)
TRAIT_W = 156

node("Game", "Control", None, {"layout_mode": 3, "anchors_preset": 15, "anchor_right": 1.0, "anchor_bottom": 1.0,
     "grow_horizontal": 2, "grow_vertical": 2, "mouse_filter": 2, "script": 'ExtResource("1_game")'})
node("Background", "ColorRect", ".", dict(FULL, mouse_filter=2, color="Color(0.07, 0.08, 0.11, 1)"))
node("BoardView", "Node2D", ".", {"script": 'ExtResource("2_board")'})
node("Tokens", "Node2D", "BoardView")
node("Fx", "Node2D", "BoardView", {"z_index": 20, "script": 'ExtResource("3_fx")'})
node("BattlePlayer", "Node", "BoardView", {"script": 'ExtResource("4_player")'})

# ── 上方：回合＋裝備節點、備戰倒數條 ──
node("TopBar", "PanelContainer", ".", {"layout_mode": 1, "anchors_preset": 10, "anchor_right": 1.0, "offset_left": 6.0,
     "offset_top": 6.0, "offset_right": -6.0, "offset_bottom": float(TOP_H), "grow_horizontal": 2})
node("HBox", "HBoxContainer", "TopBar", {"layout_mode": 2, "theme_override_constants/separation": 12})
node("RoundBox", "VBoxContainer", "TopBar/HBox", {"custom_minimum_size": "Vector2(118, 0)", "layout_mode": 2, "theme_override_constants/separation": 0})
label("RoundLabel", "TopBar/HBox/RoundBox", "1/24", {"theme_override_font_sizes/font_size": 15, "theme_override_colors/font_color": GOLD})
node("RewardDots", "Control", "TopBar/HBox/RoundBox", {"custom_minimum_size": "Vector2(112, 8)", "layout_mode": 2, "script": 'ExtResource("5_dots")'})
node("Countdown", "Control", "TopBar/HBox", {"custom_minimum_size": "Vector2(0, 28)", "layout_mode": 2, "size_flags_horizontal": 3, "size_flags_vertical": 4})
node("Bar", "ProgressBar", "TopBar/HBox/Countdown", dict(FULL, mouse_filter=2, max_value=30.0, value=30.0, show_percentage="false"))
node("BarText", "HBoxContainer", "TopBar/HBox/Countdown", dict(FULL, mouse_filter=2, theme_override_constants__separation=6))
label("BarLeft", "TopBar/HBox/Countdown/BarText", "", {"size_flags_horizontal": 3, "clip_text": "true", "theme_override_font_sizes/font_size": 15, "theme_override_colors/font_outline_color": "Color(0, 0, 0, 1)", "theme_override_constants/outline_size": 4, "vertical_alignment": 1})
label("BarRight", "TopBar/HBox/Countdown/BarText", "", {"theme_override_font_sizes/font_size": 18, "theme_override_colors/font_outline_color": "Color(0, 0, 0, 1)", "theme_override_constants/outline_size": 4, "vertical_alignment": 1})
btn("SpeedButton", "TopBar/HBox", "1×", "Vector2(52, 30)")
btn("SkipButton", "TopBar/HBox", "略過", "Vector2(60, 30)")
btn("DebugButton", "TopBar/HBox", "除錯", "Vector2(56, 30)")
btn("MenuBtn", "TopBar/HBox", "選單", "Vector2(56, 30)")

# ── 左側：精簡羈絆清單（文明置頂；寬度固定，不擠壓棋盤）──
node("LeftPanel", "PanelContainer", ".", {"layout_mode": 1, "anchors_preset": 9, "anchor_bottom": 1.0, "offset_left": 6.0,
     "offset_top": float(SIDE_TOP), "offset_right": 6.0 + TRAIT_W, "offset_bottom": float(SIDE_BOTTOM), "grow_vertical": 2})
node("Scroll", "ScrollContainer", "LeftPanel", {"layout_mode": 2, "horizontal_scroll_mode": 0})
node("List", "VBoxContainer", "LeftPanel/Scroll", {"layout_mode": 2, "size_flags_horizontal": 3, "theme_override_constants/separation": 3})
btn("CivButton", "LeftPanel/Scroll/List", "", "Vector2(0, 36)", {"alignment": 0, "clip_text": "true"})
node("TraitList", "VBoxContainer", "LeftPanel/Scroll/List", {"layout_mode": 2, "theme_override_constants/separation": 3})

# ── 右側：貢獻面板（可收合）／詳細資訊 ──
node("RightPanel", "PanelContainer", ".", {"layout_mode": 1, "anchors_preset": 11, "anchor_left": 1.0, "anchor_right": 1.0,
     "anchor_bottom": 1.0, "offset_left": -286.0, "offset_top": float(SIDE_TOP), "offset_right": -6.0, "offset_bottom": float(SIDE_BOTTOM),
     "grow_horizontal": 0, "grow_vertical": 2})
node("Stack", "VBoxContainer", "RightPanel", C)
node("LeaderHost", "VBoxContainer", "RightPanel/Stack", {"layout_mode": 2, "size_flags_vertical": 3})
node("DetailBox", "VBoxContainer", "RightPanel/Stack", {"visible": "false", "layout_mode": 2, "size_flags_vertical": 3})
node("Header", "HBoxContainer", "RightPanel/Stack/DetailBox", C)
label("DetailTitle", "RightPanel/Stack/DetailBox/Header", "", {"size_flags_horizontal": 3, "theme_override_colors/font_color": GOLD, "clip_text": "true"})
btn("CloseDetail", "RightPanel/Stack/DetailBox/Header", "×", "Vector2(40, 32)")
node("Scroll", "ScrollContainer", "RightPanel/Stack/DetailBox", {"layout_mode": 2, "size_flags_vertical": 3, "horizontal_scroll_mode": 0})
node("Body", "VBoxContainer", "RightPanel/Stack/DetailBox/Scroll", {"layout_mode": 2, "size_flags_horizontal": 3})
btn("SellButton", "RightPanel/Stack/DetailBox", "出售", "Vector2(0, 42)")
# 背包（V0.4）：拖曳裝備到棋子，或點選裝備後再點棋子
node("BagBox", "VBoxContainer", "RightPanel/Stack", {"visible": "false", "layout_mode": 2, "size_flags_vertical": 3})
node("Header", "HBoxContainer", "RightPanel/Stack/BagBox", C)
label("BagTitle", "RightPanel/Stack/BagBox/Header", "背包", {"size_flags_horizontal": 3, "theme_override_colors/font_color": GOLD, "clip_text": "true"})
btn("CloseBag", "RightPanel/Stack/BagBox/Header", "×", "Vector2(40, 32)")
label("BagHint", "RightPanel/Stack/BagBox", "", {"autowrap_mode": 3, "theme_override_font_sizes/font_size": 13, "theme_override_colors/font_color": "Color(0.62, 0.66, 0.74, 1)"})
node("Scroll", "ScrollContainer", "RightPanel/Stack/BagBox", {"layout_mode": 2, "size_flags_vertical": 3, "horizontal_scroll_mode": 0})
node("List", "VBoxContainer", "RightPanel/Stack/BagBox/Scroll", {"layout_mode": 2, "size_flags_horizontal": 3, "theme_override_constants/separation": 4})

# ── 羈絆／文明說明（浮動，不參與版面）──
node("TraitPopover", "PanelContainer", ".", {"visible": "false", "layout_mode": 0, "offset_left": 170.0, "offset_top": 60.0,
     "offset_right": 500.0, "offset_bottom": 200.0, "mouse_filter": 0})
node("Scroll", "ScrollContainer", "TraitPopover", {"custom_minimum_size": "Vector2(330, 0)", "layout_mode": 2, "horizontal_scroll_mode": 0})
rich("Text", "TraitPopover/Scroll", {"theme_override_font_sizes/normal_font_size": 14, "theme_override_font_sizes/bold_font_size": 14})

# ── 底部：資源列＋XP 條（與商店同寬）＋商店 ──
node("BottomBar", "PanelContainer", ".", {"layout_mode": 1, "anchors_preset": 12, "anchor_top": 1.0, "anchor_right": 1.0,
     "anchor_bottom": 1.0, "offset_left": 6.0, "offset_top": -float(BOTTOM_H), "offset_right": -6.0, "offset_bottom": -6.0,
     "grow_horizontal": 2, "grow_vertical": 0})
node("VBox", "VBoxContainer", "BottomBar", {"layout_mode": 2, "theme_override_constants/separation": 4})
node("RowA", "HBoxContainer", "BottomBar/VBox", {"layout_mode": 2, "theme_override_constants/separation": 8})
node("ResBox", "HBoxContainer", "BottomBar/VBox/RowA", {"custom_minimum_size": f"Vector2({LEFT_W}, 28)", "layout_mode": 2, "theme_override_constants/separation": 4})
node("XpBox", "Control", "BottomBar/VBox/RowA", {"custom_minimum_size": "Vector2(0, 28)", "layout_mode": 2, "size_flags_horizontal": 3})
node("XpBar", "ProgressBar", "BottomBar/VBox/RowA/XpBox", dict(FULL, mouse_filter=2, max_value=2.0, show_percentage="false"))
node("XpText", "HBoxContainer", "BottomBar/VBox/RowA/XpBox", dict(FULL, mouse_filter=2))
label("XpLeft", "BottomBar/VBox/RowA/XpBox/XpText", " 0/2 XP", {"size_flags_horizontal": 3, "vertical_alignment": 1, "theme_override_font_sizes/font_size": 15, "theme_override_colors/font_outline_color": "Color(0, 0, 0, 1)", "theme_override_constants/outline_size": 4})
node("XpRight", "HBoxContainer", "BottomBar/VBox/RowA/XpBox/XpText", {"layout_mode": 2, "mouse_filter": 2, "theme_override_constants/separation": 3})
btn("BagButton", "BottomBar/VBox/RowA", "背包 0", f"Vector2({RIGHT_W}, 28)")
node("RowB", "HBoxContainer", "BottomBar/VBox", {"layout_mode": 2, "size_flags_vertical": 3, "theme_override_constants/separation": 8})
node("LeftButtons", "VBoxContainer", "BottomBar/VBox/RowB", {"custom_minimum_size": f"Vector2({LEFT_W}, 0)", "layout_mode": 2})
btn("RerollButton", "BottomBar/VBox/RowB/LeftButtons", "", "Vector2(0, 36)", {"size_flags_vertical": 3})
btn("CivUpButton", "BottomBar/VBox/RowB/LeftButtons", "", "Vector2(0, 36)", {"size_flags_vertical": 3})
node("ShopSlots", "HBoxContainer", "BottomBar/VBox/RowB", {"layout_mode": 2, "size_flags_horizontal": 3, "theme_override_constants/separation": 6})
for i in range(5):
    btn(f"Slot{i}", "BottomBar/VBox/RowB/ShopSlots", "", "Vector2(90, 76)", {"size_flags_horizontal": 3, "clip_text": "true"})
node("RightButtons", "VBoxContainer", "BottomBar/VBox/RowB", {"custom_minimum_size": f"Vector2({RIGHT_W}, 0)", "layout_mode": 2})
# V0.5：取消開始戰鬥按鈕（倒數歸零自動開戰）
btn("LockButton", "BottomBar/VBox/RowB/RightButtons", "", "Vector2(0, 76)", {"size_flags_vertical": 3})

node("BigCountdown", "Label", ".", {"visible": "false", "layout_mode": 1, "anchors_preset": 5, "anchor_left": 0.5, "anchor_right": 0.5,
     "offset_left": -80.0, "offset_top": 230.0, "offset_right": 80.0, "offset_bottom": 340.0, "grow_horizontal": 2,
     "mouse_filter": 2, "theme_override_colors/font_color": "Color(1, 0.4, 0.35, 1)", "theme_override_colors/font_outline_color": "Color(0, 0, 0, 1)",
     "theme_override_constants/outline_size": 10, "theme_override_font_sizes/font_size": 84, "horizontal_alignment": 1, "vertical_alignment": 1, "text": '"5"'})

# ── 裝備三選一 ──
node("RewardOverlay", "CenterContainer", ".", dict(FULL, visible="false", mouse_filter=0))
node("Panel", "PanelContainer", "RewardOverlay", {"custom_minimum_size": "Vector2(720, 0)", "layout_mode": 2})
node("VBox", "VBoxContainer", "RewardOverlay/Panel", {"layout_mode": 2, "theme_override_constants/separation": 10})
label("RewardTitle", "RewardOverlay/Panel/VBox", "裝備獎勵", {"theme_override_font_sizes/font_size": 22, "horizontal_alignment": 1, "theme_override_colors/font_color": GOLD})
node("Cards", "HBoxContainer", "RewardOverlay/Panel/VBox", {"layout_mode": 2, "theme_override_constants/separation": 10})
label("RewardHint", "RewardOverlay/Panel/VBox", "選擇一件加入背包（選擇時不計備戰時間）", {"horizontal_alignment": 1, "theme_override_font_sizes/font_size": 13, "theme_override_colors/font_color": "Color(0.62, 0.66, 0.74, 1)"})

# ── 裝備資訊／背包選擇 ──
node("ItemOverlay", "CenterContainer", ".", dict(FULL, visible="false", mouse_filter=0))
node("Panel", "PanelContainer", "ItemOverlay", {"custom_minimum_size": "Vector2(420, 0)", "layout_mode": 2})
node("VBox", "VBoxContainer", "ItemOverlay/Panel", {"layout_mode": 2, "theme_override_constants/separation": 8})
label("ItemTitle", "ItemOverlay/Panel/VBox", "", {"theme_override_font_sizes/font_size": 20, "theme_override_colors/font_color": GOLD})
node("ItemScroll", "ScrollContainer", "ItemOverlay/Panel/VBox", {"custom_minimum_size": "Vector2(0, 240)", "layout_mode": 2, "horizontal_scroll_mode": 0})
node("ItemBody", "VBoxContainer", "ItemOverlay/Panel/VBox/ItemScroll", {"layout_mode": 2, "size_flags_horizontal": 3, "theme_override_constants/separation": 6})
node("ItemButtons", "HBoxContainer", "ItemOverlay/Panel/VBox", {"layout_mode": 2, "theme_override_constants/separation": 8, "alignment": 1})

# ── 選單／除錯／確認／提示 ──
node("MenuOverlay", "CenterContainer", ".", dict(FULL, visible="false", mouse_filter=0))
node("Panel", "PanelContainer", "MenuOverlay", {"custom_minimum_size": "Vector2(380, 0)", "layout_mode": 2})
node("VBox", "VBoxContainer", "MenuOverlay/Panel", {"layout_mode": 2, "theme_override_constants/separation": 10})
label("MenuTitle", "MenuOverlay/Panel/VBox", "暫停（備戰倒數已暫停）", {"theme_override_font_sizes/font_size": 22, "horizontal_alignment": 1})
btn("ResumeButton", "MenuOverlay/Panel/VBox", "繼續遊戲", "Vector2(0, 50)")
btn("CodexButton", "MenuOverlay/Panel/VBox", "規則／棋子圖鑑", "Vector2(0, 50)")
btn("SaveQuitButton", "MenuOverlay/Panel/VBox", "存檔並回主選單", "Vector2(0, 50)")
btn("AbandonButton", "MenuOverlay/Panel/VBox", "放棄這局（清除存檔）", "Vector2(0, 50)")
node("DebugPanel", "PanelContainer", ".", {"visible": "false", "layout_mode": 1, "anchors_preset": 5, "anchor_left": 0.5,
     "anchor_right": 0.5, "offset_left": -230.0, "offset_top": 64.0, "offset_right": 230.0, "offset_bottom": 340.0, "grow_horizontal": 2})
node("VBox", "VBoxContainer", "DebugPanel", {"layout_mode": 2, "theme_override_constants/separation": 8})
label("DebugTitle", "DebugPanel/VBox", "除錯工具（正式版不會出現；開啟時倒數暫停）", {"theme_override_colors/font_color": "Color(1, 0.6, 0.4, 1)"})
node("RoundRow", "HBoxContainer", "DebugPanel/VBox", C)
label("RoundLabel", "DebugPanel/VBox/RoundRow", "跳到回合")
node("RoundSpin", "SpinBox", "DebugPanel/VBox/RoundRow", {"layout_mode": 2, "min_value": 1.0, "max_value": 24.0, "value": 1.0})
btn("JumpButton", "DebugPanel/VBox/RoundRow", "選關", "Vector2(80, 40)")
node("Row2", "HBoxContainer", "DebugPanel/VBox", C)
btn("GoldButton", "DebugPanel/VBox/Row2", "+20 金幣", "Vector2(0, 40)", {"size_flags_horizontal": 3})
btn("LevelButton", "DebugPanel/VBox/Row2", "文明 +1 級", "Vector2(0, 40)", {"size_flags_horizontal": 3})
node("Row3", "HBoxContainer", "DebugPanel/VBox", C)
btn("ItemButton", "DebugPanel/VBox/Row3", "+1 隨機裝備", "Vector2(0, 40)", {"size_flags_horizontal": 3})
btn("WinButton", "DebugPanel/VBox/Row3", "直接過關→下一關", "Vector2(0, 40)", {"size_flags_horizontal": 3})
btn("CloseDebugButton", "DebugPanel/VBox", "關閉", "Vector2(0, 40)")
node("AbandonConfirm", "ConfirmationDialog", ".", {"title": '"放棄這局"', "size": "Vector2i(380, 150)",
     "ok_button_text": '"放棄並回主選單"', "cancel_button_text": '"取消"', "dialog_text": '"確定要放棄目前的遠征嗎？存檔會被清除。"'})
node("Toasts", "VBoxContainer", ".", {"layout_mode": 1, "anchors_preset": 5, "anchor_left": 0.5, "anchor_right": 0.5,
     "offset_left": -300.0, "offset_top": 66.0, "offset_right": 300.0, "offset_bottom": 200.0, "grow_horizontal": 2,
     "mouse_filter": 2, "theme_override_constants/separation": 4})

header = '''[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ui/game_screen.gd" id="1_game"]
[ext_resource type="Script" path="res://scripts/ui/board_view.gd" id="2_board"]
[ext_resource type="Script" path="res://scripts/ui/battle_fx.gd" id="3_fx"]
[ext_resource type="Script" path="res://scripts/ui/battle_player.gd" id="4_player"]
[ext_resource type="Script" path="res://scripts/ui/reward_dots.gd" id="5_dots"]
'''
out = header + '\n' + '\n\n'.join(nodes) + '\n'
out = out.replace("theme_override_constants__separation", "theme_override_constants/separation")
open('scenes/game.tscn', 'w', encoding='utf-8').write(out)
print(len(nodes), "nodes")
