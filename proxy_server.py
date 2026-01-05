import os
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import google.generativeai as genai
from typing import Optional
import uvicorn
from dotenv import load_dotenv

# تحميل متغيرات البيئة (مثل مفتاح API)
load_dotenv()

# إعداد FastAPI
app = FastAPI()

# --- إعدادات الـ CORS الهامة جداً لعمل تطبيق Flutter Web ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # يسمح بالوصول من أي مكان (بما في ذلك localhost)
    allow_credentials=True,
    allow_methods=["*"],  # يسمح بجميع أنواع الطلبات (GET, POST, etc.)
    allow_headers=["*"],  # يسمح بجميع الـ Headers
)

# إعداد مفتاح API الخاص بـ Gemini
# تأكد من إضافة GEMINI_API_KEY في إعدادات Environment Variables في موقع Render
GENI_API_KEY = os.getenv("GEMINI_API_KEY")
genai.configure(api_key=GENI_API_KEY)

@app.get("/")
def read_root():
    return {"status": "Server is running successfully!"}

@app.post("/analyze")
async def analyze(
    text: Optional[str] = Form(None),
    youtube: Optional[str] = Form(None),
    analysis_type: str = Form("summary"),
    file: Optional[UploadFile] = File(None)
):
    try:
        # تجهيز نموذج Gemini
        model = genai.GenerativeModel('gemini-1.5-flash')
        
        prompt_content = f"الرجاء القيام بـ {analysis_type} للمحتوى التالي:\n"
        
        if text:
            prompt_content += f"النص: {text}\n"
        
        if youtube:
            prompt_content += f"رابط يوتيوب (قم بتحليل المحتوى بناءً على المعلومات المتاحة): {youtube}\n"
            
        if file:
            # في حال وجود ملف PDF، يتم قراءة محتواه (تحتاج لمكتبة إضافية مثل PyMuPDF إذا أردت معالجة معقدة)
            # هنا نفترض معالجة أولية للنص
            file_content = await file.read()
            prompt_content += f"محتوى الملف المرفق متاح للمعالجة.\n"

        # إرسال الطلب لـ Gemini
        response = model.generate_content(prompt_content)
        
        return {
            "analysis": response.text,
            "main_topics": 5, # قيم افتراضية للتجربة
            "key_points": 10,
            "status": "success"
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port) 
    