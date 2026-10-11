# 原生炮击特效的事件时间修复

日期：2026-10-11。此修复只修改 `game/presentation/combat/combat_effects.gd`，不修改海浪、水花、尾迹、物理或运行时。

## 问题与行为

`fire`、`hit` 原先没有将事件时间传入 `_puff`，迟到的炮击会从当前时刻重新播放。其他已有的断桅和毁船事件虽然使用原时间，首帧仍采用出生位置、大小与透明度，下一快照才追上事件年龄。

现在所有炮口闪光、烟雾、木屑、断桅碎片和毁船烟雾使用同一原生事件时间。生成首帧直接按当前接受时间减去事件时间计算位置、大小和透明度。未来事件不创建效果，已超过各自寿命的部分不创建；同次火炮事件可以保留仍存活的烟雾，同时省略已经结束的闪光。后续快照复用同一更新函数。

保持既有即时事件外观、160 个烟雾/碎片预算、事件去重、回退清理和沉船表面泡沫路径。没有增加独立时钟或粒子积分，也没有修改质量参数。

## TDD 和局部验证

新回归测试 `tests/test_reference_event_time.gd` 先在原产品代码上运行，31 项断言中 17 项失败，退出码 1，无脚本解析错误。失败项包括迟到首帧、过期/未来事件、原始寿命、回退重放和断桅首帧。最小修复后同一测试 31 项全部通过。

Godot 4.7.2 `ed1daf0bf` 的本轮 headless 检查：

| 测试 | 断言 | 失败 |
| --- | ---: | ---: |
| `test_reference_event_time.gd` | 31 | 0 |
| `test_pirates_water_effects.gd` | 127 | 0 |
| `test_reference_presentation_integration.gd` | 7 | 0 |
| `test_reference_water_volume.gd` | 133 | 0 |
| 合计 | 298 | 0 |

四项运行退出码均为 0，无脚本错误。目标文件 `git diff --check` 通过。新测试由现有 `tools/verify-godot.mjs` 的 `test_*.gd` 发现机制自动选入。

示例运行命令：

```powershell
rtk proxy "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless --path "C:/Users/dains/Documents/Git/ming-armada" --script res://tests/test_reference_event_time.gd
```

本轮没有运行 GPU、性能测试或完整测试；根线程负责冻结后的完整测试与最终可执行程序验收。此前拟议的性能微测未执行，临时脚本已删除。
