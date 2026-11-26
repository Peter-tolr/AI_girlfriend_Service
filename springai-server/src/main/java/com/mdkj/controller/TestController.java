package com.mdkj.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class TestController {

    /** 连通性检查：不依赖任何 AI 能力，用于确认服务本身是否起来了 */
    @GetMapping("/test")
    public String test() {
        return "hello spring boot and spring ai!";
    }
}
