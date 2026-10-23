const express = require('express');
const app = express();
const PORT = 3000;

// 中間件 (Middleware)：讓後端可以解析前端傳來的 JSON 資料
app.use(express.json());

// 路由 1：GET 請求 (獲取資料)
app.get('/api/users', (req, res) => {
    res.json([
        { id: 1, name: 'Alex', role: 'Developer' },
        { id: 2, name: 'Bob', role: 'Designer' }
    ]);
});

// 路由 2：POST 請求 (新增資料)
app.post('/api/users', (req, res) => {
    const newUser = req.body; // 接收前端傳來的資料
    console.log('收到新用戶：', newUser);
    
    // 回傳成功狀態與資料
    res.status(201).json({
        message: '用戶建立成功！',
        data: newUser
    });
});

// 啟動伺服器並監聽 Port 3000
app.listen(PORT, () => {
    console.log(`後端伺服器已啟動：http://localhost:${PORT}`);
});
