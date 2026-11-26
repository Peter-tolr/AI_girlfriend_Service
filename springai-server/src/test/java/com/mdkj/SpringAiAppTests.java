package com.mdkj;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 启动冒烟测试：不依赖真实 API Key，也不访问网络。
 *
 * <p>api-key 给个占位值，只为让对话相关 Bean 能被创建，不会真的发请求。
 * 人设文件优先读工作目录下的 companion_skill/，测试时也读得到。</p>
 */
@SpringBootTest(properties = {
        "spring.ai.openai.api-key=test-key"
})
@AutoConfigureMockMvc
class SpringAiAppTests {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void contextLoads() {
        // 上下文能启动，说明 Controller / Advisor / 人设加载装配没问题
    }

    @Test
    void testEndpointIsReachable() throws Exception {
        mockMvc.perform(get("/test"))
                .andExpect(status().isOk())
                .andExpect(content().string("hello spring boot and spring ai!"));
    }
}
