import sqlite3

conn = sqlite3.connect("hospital.db")
cursor = conn.cursor()

# 建立症狀對照表
cursor.execute("""
CREATE TABLE IF NOT EXISTS symptom_mapping (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    keyword TEXT,
    department TEXT,
    severity TEXT
)
""")

# 建立醫院資料表
cursor.execute("""
CREATE TABLE IF NOT EXISTS hospitals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    level TEXT,
    address TEXT,
    lat REAL,
    lng REAL
)
""")

# 清空舊資料（避免重複）
cursor.execute("DELETE FROM symptom_mapping")
cursor.execute("DELETE FROM hospitals")

# 症狀測試資料
symptom_data = [
    ("感冒", "耳鼻喉科", "輕"),
    ("喉嚨", "耳鼻喉科", "輕"),
    ("流鼻水", "耳鼻喉科", "輕"),
    ("咳嗽", "耳鼻喉科", "輕"),
    ("發燒", "家醫科", "中"),
    ("頭痛", "家醫科", "中"),
    ("肚子", "腸胃科", "中"),
    ("腹瀉", "腸胃科", "中"),
    ("胸痛", "心臟內科", "重"),
    ("呼吸困難", "胸腔內科", "重"),
    ("頭暈", "神經內科", "中"),
    ("關節痛", "骨科", "輕"),
]

cursor.executemany(
    "INSERT INTO symptom_mapping (keyword, department, severity) VALUES (?, ?, ?)",
    symptom_data
)

# 三家醫院資料（座標為示意）
hospital_data = [
    ("大林慈濟醫院", "區域醫院", "嘉義縣大林鎮", 23.5986, 120.4567),
    ("臺大醫院雲林分院", "區域醫院", "雲林縣斗六市", 23.7090, 120.4310),
    ("嘉義基督教醫院", "區域醫院", "嘉義市東區", 23.4800, 120.4490),
]

cursor.executemany(
    "INSERT INTO hospitals (name, level, address, lat, lng) VALUES (?, ?, ?, ?, ?)",
    hospital_data
)

conn.commit()
conn.close()
print("資料庫初始化完成！（含醫院資料）")