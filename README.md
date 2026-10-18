# inZOI 寵物模組「毛孩之家 Paw Home」（暫定）

讓 inZOI 的 Zoi 能領養流浪貓或收容所的貓、在家照顧牠，玩法參考 The Sims 4《貓狗成群》。inZOI 目前還沒有寵物系統，這個模組用官方 ModKit 的 Lua 腳本和 Overlay UI 來補上。語系：繁體中文、English。

## 狀態

寵物引擎與介面已完成，並在模擬環境通過 67 項自動測試；**還沒接上真正的遊戲**（要先做第 0 階段探勘）。

## 現在就能玩玩看（不用開遊戲）

```bash
pip install lupa
python3 tools/preview_server.py
# 開啟 http://127.0.0.1:8765/?preview=1
```

用的是真正的 Lua 引擎，頁面最下面的「預覽工具」可以快轉遊戲時間，看需求下降、貓長大、被動保員帶走與付費領回。

## 跑測試

```bash
pip install lupa
python3 -I tests/run.py        # 67 passed, 0 failed
```

## 文件

| 文件 | 內容 |
|---|---|
| [docs/sims4-pet-system.md](docs/sims4-pet-system.md) | Sims 4 寵物系統研究與本模組的對照表（做了什麼、沒做什麼） |
| [docs/pet-mod-plan.md](docs/pet-mod-plan.md) | 玩法設計、專案結構與開發進程 |
| [docs/handoff-ue4ss-session.md](docs/handoff-ue4ss-session.md) | **交接給既有的 ZoiPets（UE4SS）本機 session**：兩個專案的關係、我查到的事實、風險與建議步驟 |
| [docs/handoff-local-session.md](docs/handoff-local-session.md) | **交接給本機 Claude Code session**（含第一則要貼的訊息） |
| [docs/setup-windows.md](docs/setup-windows.md) | Windows 開發環境安裝（搭配 `scripts/setup-windows.ps1`） |
| [docs/phase0-probe.md](docs/phase0-probe.md) | 第 0 階段可行性探勘清單（接上遊戲前必做） |
| [docs/research-report.md](docs/research-report.md) | inZOI 模組製作方式與社群需求研究 |
