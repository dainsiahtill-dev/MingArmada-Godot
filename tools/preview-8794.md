# 本地预览服务 8794

访问：<http://127.0.0.1:8794/docs/narrative/zheng-zhilong/>。

局域网访问：<http://192.168.10.4:8794/docs/narrative/zheng-zhilong/>。

用户指定的frp公网入口：<http://8.138.113.205:18794/docs/narrative/zheng-zhilong/?edition=11#top>。公网入口是否可用，必须单独经隧道验证，不能由本地200推定。

最新实测：2026-10-23 22:23（北京时间），该公网入口已显示V8。页面、story-data.js、JSON、小说正文、完整文学剧本、游戏场景稿六项请求均200且与本地文件逐字节一致，见[公网验证记录](../docs/narrative/rewrites/v8-engagement-2026-10-23/public-http-verification.json)。这是本机经公网地址的实测，不是另一台独立外网设备验证。下文较早的公网超时结论保留为历史记录，不代表本次结果；本次未修改隧道或服务配置。

**当前状态：2026-10-23 21:53已通过该公网入口验证。** frpc设备为`192.168.10.3`，上游为`192.168.10.4:8794`。页面GET返回200，接收内容与本地index.html逐字节一致；脚本、CSS、图片200，项目源码、Git文件、目录列表403。源站日志实际记录来自192.168.10.3的成功探测。完整八项收据见`preview-8794-frp-verification.json`。

用户随后明确：本图卷的frp配置在另一台设备，不在本机。本机MatrixMeshService下发现的frpc不能据此认定属于该映射；停止检查该服务，不修改其配置。异机frpc应以`192.168.10.4:8794`为上游，而非该设备自己的`127.0.0.1:8794`。如果frpc通过VPN地址连接，应先核对实际源地址，再按明确的单设备/网段设置Windows规则。

Windows 任务名：`MingArmada Preview 8794`。以当前用户的普通权限运行，登录时启动；无运行时限，不因电池供电停止。另有每分钟重复触发，已有实例时忽略，避免重复启动；意外结束后由下一次触发恢复。失败重试额外配置为间隔一分钟、最多999次，但保活不只依赖该设置。

任务直接运行本机 `pythonw.exe` 与 `tools/run-preview-8794.py`，不依赖聊天、编辑器或临时终端。Python标准库HTTP服务监听IPv4接口，应用层不再限制请求来源IP，以支持frp。所有来源（包括回环、LAN和代理转发）均限于`docs/narrative/zheng-zhilong/`内的图卷及素材。解析后的真实文件路径必须仍位于图卷目录，禁止目录列表及访问项目其他文件；不信任Host或X-Forwarded-For来绕过路径限制。文件更新后刷新页面即可。

日志：`%LOCALAPPDATA%\MingArmada\preview-8794\server.log`。重新启动时如日志超过5MiB，保留一份 `server.previous.log`。

注册脚本 `tools/register-preview-8794.ps1` 使用本机Python路径，不保存密码、不改变执行策略。已存在同名任务或端口占用时拒绝覆盖，须先检查归属。

防火墙规则`MingArmada-Preview-8794-LAN`允许当前Python进程在`192.168.10.4:8794/TCP`接收`192.168.10.0/24`来源的连接。WLAN当前为Public，因此规则适用于所有配置文件，但地址、来源、端口和程序均受限。没有改变网络类别或关闭防火墙。需要重新注册该规则时，以管理员身份运行`tools/enable-preview-8794-lan.ps1`；已有同名规则若不符合预期范围，脚本拒绝静默覆盖。

实际导致异机frpc请求不通的冲突：Windows自动生成的`TCP Query User…C:\python314\pythonw.exe`为Public配置文件显式阻止所有TCP端口，优先于上述允许规则。已由管理员脚本`tools/repair-preview-8794-firewall.ps1`将这条TCP阻止范围缩到`1-8793,8795-65535`，仅避开8794。UDP阻止保持不变。修复前规则备份和操作收据分别位于`%LOCALAPPDATA%\MingArmada\preview-8794\firewall-python-tcp-block-before.json`及`firewall-repair.json`。以后若重新生成应用阻止规则，应检查此冲突，不重复堆加允许规则。公网成功发生在这项修复之后，未修改异机frp配置。

frpc若与服务同机，应转发至`127.0.0.1:8794`，无需为公网源IP扩大Windows入站规则。若frpc在另一台局域网电脑上，可转发至`192.168.10.4:8794`，使用既有LAN规则。本服务不提供项目根目录；需要其他页面另设明确发布目录，不应通过伪装代理头绕过限制。

查看任务：

```powershell
rtk proxy powershell -NoProfile -Command 'Get-ScheduledTask -TaskName "MingArmada Preview 8794" | Select-Object TaskName,State'
```

需要主动停用时，先禁用登录触发，再停止当前任务：

```powershell
rtk proxy powershell -NoProfile -Command 'Disable-ScheduledTask -TaskName "MingArmada Preview 8794"'
rtk proxy powershell -NoProfile -Command 'Stop-ScheduledTask -TaskName "MingArmada Preview 8794"'
```

恢复：

```powershell
rtk proxy powershell -NoProfile -Command 'Enable-ScheduledTask -TaskName "MingArmada Preview 8794"'
rtk proxy powershell -NoProfile -Command 'Start-ScheduledTask -TaskName "MingArmada Preview 8794"'
```

可用边界：这是本机预览服务；电脑关机、休眠或用户注销期间不可访问。重新登录后由任务启动。没有通过重启或注销用户来测试登录触发，实际自动重启验证另记于本目录验收文件。

2026-10-23首次恢复试验仅设置失败重试，强制结束进程后85秒未恢复，任务记录退出码4294967295。因此补充每分钟时间触发，不将失败重试参数本身冒充已验证保活。第二次试验的实际HTTP HEAD恢复结果见 `preview-8794-recovery.json`。

2026-10-23局域网修复：原监听127.0.0.1且无8794防火墙规则，LAN地址请求超时。本轮修正监听并经Windows管理员确认添加规则。本机分别通过回环和LAN地址实际请求，页面、数据、CSS、图片均200；LAN源码、Git文件、编码路径越界及目录列表均403，九项通过，见`preview-8794-lan-verification.json`。这些请求均来自服务所在电脑，没有冒充另一台局域网设备的实际连接证据。图卷之外的本地研究Markdown链接仍不对局域网开放；图卷内容、图像、下载数据正常开放。

同日早期frp排查记录：撤掉应用层来源IP白名单后，源站图卷与素材可用，但公网HTTP仍超时。此时误把本机MatrixMeshService下的frpc当作线索；用户明确异机frpc在192.168.10.3后，停止本机配置检查，没有修改MatrixMesh。随后找到并修正上述显式阻止规则，公网链路才实际成功。早期“尚未验收”的结论已由当前公网请求证据更新；独立手机网络和浏览器目视仍未代测。
