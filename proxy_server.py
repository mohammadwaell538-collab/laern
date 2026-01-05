import os
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import google.generativeai as genai
from typing import Optional
import uvicorn
from dotenv import load_dotenv

# 1. تحميل ملف .env (للتجربة المحلية فقط)
load_dotenv()

# 2. إعداد FastAPI
app = FastAPI()

# 3. إعدادات الـ CORS لضمان عمل تطبيق Flutter Web بدون مشاكل أمنية
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # يسمح بالوصول من أي رابط (بما في ذلك localhost)
    allow_credentials=True,
    allow_methods=["*"],  # يسمح بجميع أنواع الطلبات (GET, POST, etc.)
    allow_headers=["*"],  # يسمح بجميع الـ Headers
)

# 4. إعداد مفتاح API الخاص بـ Gemini
# سيقوم الكود بالبحث عن متغير اسمه GEMINI_API_KEY في إعدادات موقع Render
api_key = os.getenv("GEMINI_API_KEY")

if api_key:
    genai.configure(api_key=api_key)
else:
    print("Warning: GEMINI_API_KEY not found. Please add it in Render settings.")

@app.get("/")
def read_root():
    return {"status": "الخادم يعمل بنجاح!"}

@app.post("/analyze")
async def analyze(
    text: Optional[str] = Form(None),
    youtube: Optional[str] = Form(None),
    analysis_type: str = Form("summary"),
    file: Optional[UploadFile] = File(None)
):
    try:
        # اختيار نموذج Gemini (flash هو الأسرع والأفضل للخطة المجانية)
        model = genai.GenerativeModel('gemini-1.5-flash')
        
        # بناء نص الأمر (Prompt)
        prompt_content = f"الرجاء القيام بـ {analysis_type} للمحتوى التالي:\n"
        
        if text:
            prompt_content += f"النص المرسل: {text}\n"
        
        if youtube:
            prompt_content += f"رابط فيديو يوتيوب للتحليل: {youtube}\n"
            
        if file:
            # ملاحظة: لمعالجة ملفات PDF بشكل متقدم قد تحتاج لمكتبة إضافية
            # هنا نقوم بتأكيد استقبال الملف وإخبار الذكاء الاصطناعي بوجوده
            prompt_content += f"اسم الملف المرفق: {file.filename}\n"

        # إرسال الطلب إلى Gemini
        response = model.generate_content(prompt_content)
        
        # إرجاع النتيجة لتطبيق Flutter
        return {
            "analysis": response.text,
            "status": "success"
        }

    except Exception as e:
        # في حال حدوث خطأ، سيظهر لك السبب في الـ Logs على Render
        raise HTTPException(status_code=500, detail=str(e))

# 5. تشغيل السيرفر (Render يستخدم المنفذ PORT تلقائياً)
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)