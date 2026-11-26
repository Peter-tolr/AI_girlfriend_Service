import {defineConfig} from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    host: 'localhost', // ip地址
    port: 6051, // 开发模式端口
    // 开发模式下把 /api 转发给后端，前端代码里用相对地址即可
    proxy: {
      '/api': {
        target: 'http://localhost:5501',
        changeOrigin: true,
      },
    },
  },
  build: {
    // 直接产出到 Spring Boot 的静态资源目录：java -jar 时页面和接口同一个端口、同一个进程
    outDir: '../springai-server/src/main/resources/static',
    emptyOutDir: true,
  },
})
