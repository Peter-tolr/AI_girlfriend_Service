# springai-web

AISmartCustomerService 的 Vue 3 + Vite 前端，完整说明见仓库根目录的 [README.md](../README.md)。

```bash
npm install
npm run dev    # 开发模式：http://localhost:6051，/api 自动代理到 5501
npm run build  # 产物输出到 ../springai-server/src/main/resources/static（打包进 jar）
```

前端源码改动后，执行 `npm run build` 再重新打包/启动后端，即可在 <http://localhost:5501> 看到新页面。
