# 刺绣 M1 检查

- `node scripts/embroidery-tests/geometry.test.cjs` 不依赖浏览器。
- `browser-smoke.cjs`、`acceptance.cjs`、`interaction.cjs` 使用 Playwright Core 和短时 `/snap/bin/chromium`，退出时关闭浏览器。
- 测试服务器在 `127.0.0.1:18039` 提供 Embroidery 网页，`/data/` 指向部署的刺绣静态资源，`/font/` 指向字体文件。本机测试驱动在 `/root/workroom/embroidery/build/test_server.py`，无生产写入端点。
- 所有作品与图像都由测试合成；不读取私聊、日记或私人相册，不向聊天发卡片。
- 浏览器依赖装在隔离的 `/root/workroom/embroidery/build/node_modules`。运行仓库内测试可设置 `NODE_PATH` 指向该目录。
- 覆盖：确定性针脚／导出、撤销重做、繁体笔顺、15 个字体入口、6 种布料×5 种形状、四角镜像、弯曲绕边、手绘一笔撤销、印花／补丁、草稿重开、窄屏尺寸。
- 此处通过不能替代 iOS 的编译、WKWebView 自定义资源协议、相册权限与键盘实机验证。

## M2

- `python3 scripts/embroidery-tests/store_test.py`：临时 SQLite 与假聊天传输，验证定版幂等、回收站、替换格子、发送去重和丢失响应后的只读核对（8 项）。
- `NODE_PATH=/root/workroom/embroidery/build/node_modules node scripts/embroidery-tests/m2_browser.cjs`：请求全部截到浏览器假服务，验证完成不自动发送、回放、拼布被、新版本选项。
- 命令 `/root/rhysel/stitch.py '测试文字' --dry-run --output-dir <目录>` 仅生成本地 PNG/JSON；只有显式 `--send` 才写正式作品并发送，测试禁止使用。
- 后端源码位于 alcove-backend 的 embroidery_api.py、embroidery_store.py、embroidery_render.py；不属于 App 提交。
- 发送超时不自动重投；再点发送仅核对已存消息，找不到时保留待确认状态，避免重复叫醒。

## 1012 样卡修复

- `issues1012.cjs`：6 种布料随机色对比度≥3、每池至少3色；5类点状素材识别；字距与竖版操作。需同上临时静态测试服务器。
- 字号12–160、行距1–2、字距0–40；素材对象线粗1–10。尺寸切换只按比例移动对象起点，不拉扯字形；角花继续贴角。
- 珍珠用距离峰值分离近圆颗粒并绣圆环，属于近似描绘，不是实心缎面针。
- CLI 支持 `stitch.py --doc <json> --dry-run --output-dir <目录>`；快捷英文保留完整单词。命令文件在 `/root/rhysel/stitch.py`，不在 App 仓库。
- 1012 工作室接手合入：毛边重做（沿布边法线、长短粗细随机、长松线头、牛仔白毛边、毛毡只起绒）＋布底两层浮起阴影，布四周留边 20→50（cloth 缓存与 exportPNG 同步）；背景色 export_bg（白 / 米白 / 雾粉 / 雾蓝 / 炭灰 / 透明＋自定义，默认米白），布料抽屉和成品页都能换，编辑画面同框显示。上面七套测试在合入后全部重跑通过。
