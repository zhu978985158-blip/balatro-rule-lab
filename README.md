# 规则实验室 / Rule Lab

这是一个只修改原版规则、不新增 Joker 或卡牌资源的 Balatro Steamodded Mod。

## 当前版本

- Mod 版本：`0.2.0`
- 目标：macOS Steam
- 依赖：Lovely `>=0.9.0`、Steamodded `>=1.0.0~BETA`
- 默认状态：全部开关关闭
- 生效时机：对局中即时生效

## 对局内使用

进入牌局后随时按 **F8** 打开“规则实验室 · 当前牌局”面板。点击开关立即生效，按“返回牌局”继续游戏。面板按四个分类分页：经济商店、出牌牌组、小丑版本、盲注连胜。

一次性规则仍按一次性处理：例如“首购免费”只影响当前商店第一件购买，“失败保底”每局一次，“首手回响”和“万能改写”每个盲注一次。关闭开关不会撤销已经获得的出牌、弃牌、现金或已结算分数，也不会刷新已经消耗的次数。

主菜单 Mods 中的配置页仍可用于设置新局的默认开关；但牌局内 F8 面板会优先修改当前牌局状态。

## 开关

经济与商店：首购免费、增强回收、商店回声。

出牌与牌组：额外行动、首手回响、万能改写。

Joker 与 Edition：Joker 超频、原版升阶、Edition 放大。

盲注与连胜：失败保底、Boss 重选、无弃牌奖励。

## 安装

先安装上面列出的 Lovely 和 Steamodded，再将本仓库文件所在的文件夹命名为 `RuleLab`，复制到：
`~/Library/Application Support/Balatro/Mods/`

启动已配置 Lovely 的 Balatro，在 Mods 列表中确认“规则实验室”已加载。

本仓库仅包含 Mod 源文件，不附带 Balatro、Lovely 或 Steamodded。卸载此 Mod 时，关闭游戏并删除 `Mods/RuleLab`。

## 兼容边界

首版按当前本机 Balatro 1.0.x 源码结构和 Steamodded API 编写。Balatro 或 Steamodded 更新后，Lovely 补丁可能需要调整。关闭全部开关时，Mod 不应改变原版牌局；若发生加载错误，先移除 `Mods/RuleLab` 文件夹即可恢复原版启动路径。

本版本尚未做 Windows 原生实机验证。
