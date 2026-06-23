# 北京出口节点 setup 脚本（无密钥）

两个脚本，**无任何私钥/密码**（只有 SSH 公钥 + 已公开的域名）。一次性入网 key 由 Claude 在第 5 步单独给（有效 1 小时）。

## 1. Windows 自启 / 电源（PowerShell）
`setup-beijing-windows.ps1` 会配好「开机自启 WSL + 永不睡眠 + 合盖不操作」。
**普通 PowerShell 就行**——脚本会自动弹 UAC 提权（点「是」）。

先把它从 WSL 拷到 Windows（在 Ubuntu 终端里跑）：

    cp ~/beijing-setup/setup-beijing-windows.ps1 /mnt/c/Users/Public/bj.ps1

再在 Windows 的 PowerShell 里跑：

    powershell -ExecutionPolicy Bypass -File C:\Users\Public\bj.ps1

（或者直接在浏览器 `github.com/rokabytedev/bj` 下载 ps1 到任意位置再这样跑。）

## 2. WSL 入网（Ubuntu 终端，第 5 步）
跟 Claude 要一个 1 小时一次性 key（形如 `hskey-auth-...`），然后：

    PREAUTH_KEY='hskey-auth-Claude给你的那串' bash ~/beijing-setup/setup-beijing.sh

跑完把结尾那段 `BEGIN-BEIJING-REPORT … END-BEIJING-REPORT` 贴回给 Claude。
