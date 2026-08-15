# DSH 会话置顶增强 · dsh-workspace-pin

给 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web 界面**左侧工作区面板**的会话列表加入「**置顶**」功能:

- 悬停任一会话,行内出现 **📌 图钉按钮**,一键置顶 / 取消置顶;
- 或使用行尾 **⋯ 菜单** →「置顶会话 / 取消置顶」;
- 被置顶的会话统一收进列表顶部的 **「置顶」区块**,按置顶时间倒序(后置顶的在上);
- 置顶状态保存在浏览器本地(`localStorage`,key 为 `dsh.workspace.view.v5`),**刷新 / 重启后依然保留**,不写入会话数据、不影响服务器端排序。

> 说明:本仓库不包含 DSH 本体。它只把 DSH 内置的 `@deepseek-ai/dsh-client-ui-workspace` 客户端 bundle 替换为打了补丁的版本。**安装前请先完全退出 DSH。**

---

## 适用版本

| 项目 | 值 |
| --- | --- |
| 目标包 | `@deepseek-ai/dsh-client-ui-workspace` |
| 支持版本 | **0.1.0-rc.5 系列**(2026-02 桌面构建,即 `persist: "dsh.workspace.view.v5"` 一代的代码) |
| 平台 | Windows(脚本为 PowerShell) |

安装脚本会先校验目标文件(哈希精确匹配,或内容锚点匹配),**版本不符会明确拒绝**,不会乱改你的文件。

## 安装

**方法一:一键脚本(推荐)**

```powershell
# 把整个仓库克隆/下载到本地后,在仓库目录中执行:
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

脚本会自动定位 DSH 安装目录(常见安装位置 + `%USERPROFILE%\.dsh` 配置目录)。如果找不到,或你有多个安装,可显式指定:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DshRoot "D:\Tools\DeepSeek Harness\resources\host"
```

脚本会:
1. 校验目标 `lib/client.js` 是否为受支持的原始版本;
2. 备份原文件为 `client.js.bak-dshpin`;
3. 写入补丁版并**回读校验**;
4. 已安装过则自动跳过(幂等)。

**方法二:手动替换**

1. 退出 DSH;
2. 找到 `…\DeepSeek Harness\resources\host\node_modules\@deepseek-ai\dsh-client-ui-workspace\lib\client.js`,备份原文件;
3. 用本仓库 `patched\client.js` 覆盖它。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

脚本会找到安装时生成的备份(`client.js.bak-dshpin`)并还原。手动替换安装的,请自行用备份还原。

## 使用

1. (重新)启动 DSH;若界面未变化,按 `Ctrl+Shift+R` 强制刷新;
2. 悬停任一会话 → 点击行内 📌 按钮,或点 ⋯ 菜单 →「置顶会话」;
3. 该会话立即移到顶部「置顶」区块,并从原工作区分组中移除(不重复显示);
4. 再次点击 📌(或菜单「取消置顶」)即回到原分组;
5. 归档的会话不会出现在置顶区;取消归档后自动恢复置顶。

## 工作原理(给维护者)

功能完全在**前端 bundle 内**实现,不涉及宿主进程:

- `createWorkspaceViewStore` 新增 `pinnedSessions`(sessionId → 置顶时间戳)状态与 `togglePin` 动作,随原有 `dsh.workspace.view.v5` 一起持久化;
- 新增 `derivePinned` 派生函数:置顶会话按置顶时间倒序,并从 `deriveGroups` / `deriveFlat` 中排除;
- `SessionNodeItem` 增加悬停图钉按钮、⋯ 菜单项与置顶标记;新增 `PinnedSection` 组件渲染顶部置顶区;
- 中英文案、CSS 同步补充。

> 注意:DSH 升级会重新写入该 bundle,补丁会被覆盖,届时重新运行安装脚本即可(若新版代码变动,请等待仓库适配)。

## 许可

补丁部分按需自用/分享;DSH 本体版权归 DeepSeek 所有。
