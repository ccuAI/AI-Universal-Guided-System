from fastapi import FastAPI
from pydantic import BaseModel
import sqlite3

app = FastAPI()

class SymptomRequest(BaseModel):
    text: str

def get_db_connection():
    conn = sqlite3.connect("hospital.db")
    conn.row_factory = sqlite3.Row
    return conn

@app.post("/api/analyze_symptom")
def analyze_symptom(request: SymptomRequest):
    text = request.text

    conn = get_db_connection()
    cursor = conn.cursor()

    # 查症狀
    cursor.execute("SELECT keyword, department, severity FROM symptom_mapping")
    symptom_rows = cursor.fetchall()

    matched_department = "家醫科"
    matched_severity = "輕"
    matched_keyword = None

    for row in symptom_rows:
        if row["keyword"] in text:
            matched_department = row["department"]
            matched_severity = row["severity"]
            matched_keyword = row["keyword"]
            break

    # 查所有醫院
    cursor.execute("SELECT id, name, level, address FROM hospitals")
    hospitals = cursor.fetchall()
    conn.close()

    # 簡單推薦邏輯（目前先推薦第一家，之後可再優化距離）
    if hospitals:
        recommended = hospitals[0]  # 先暫時固定推薦第一家
        hospital_name = recommended["name"]
        hospital_id = recommended["id"]
        hospital_level = recommended["level"]
    else:
        hospital_name = "無資料"
        hospital_id = None
        hospital_level = ""

    # 根據嚴重度產生說明文字
    if matched_severity == "輕":
        message = "您的症狀較輕微，建議就近選擇醫院。"
    elif matched_severity == "中":
        message = "建議至區域醫院就診。"
    else:
        message = "您的症狀需要較高注意，建議盡快至醫院，必要時請考慮急診。"

    return {
        "action": "recommend_hospital",
        "department": matched_department,
        "severity": matched_severity,
        "keyword": matched_keyword,
        "hospital_id": hospital_id,
        "hospital_name": hospital_name,
        "hospital_level": hospital_level,
        "message": message,
        "speech": f"根據您的症狀，建議掛{matched_department}，推薦您前往{hospital_name}",
        "next_step": "confirm_hospital"
    }