<%* tR = ""; const selected = await tp.system.suggester( ["☕ 休憩開始", "▶ 休憩終了"], ["開始", "終了"], false, "休憩" ); if (selected) { tR = "⏸ 休憩" + selected + " " + tp.date.now("HH:mm") + "\n"; } _%>
