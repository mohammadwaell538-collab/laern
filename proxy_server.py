@app.post("/analyze")
async def analyze(
    text: Optional[str] = Form(None),
    analysis_type: Optional[str] = Form("summary")
):
    try:
        # 1. التأكد من وجود المفتاح
        if not api_key:
            return {"analysis": "خطأ: مفتاح API مفقود في إعدادات Render"}

        # 2. تنظيف النص المرسل (هذا ما طلبته للتأكد من جودة النص)
        if not text or len(text.strip()) == 0:
            return {"analysis": "عذراً، النص المرسل فارغ أو غير مفهوم."}

        # 3. إعداد النموذج (استخدام gemini-1.5-flash لسرعته ودعمه للعربية)
        model = genai.GenerativeModel('gemini-1.5-flash')
        
        # 4. بناء الطلب بشكل صريح (Prompt Engineering)
        prompt = f"قم بدور محلل محتوى تعليمي. المطلوب: {analysis_type} للنص التالي باللغة العربية: \n\n {text}"
        
        # 5. إرسال الطلب
        response = model.generate_content(prompt)
        
        return {"analysis": response.text}
        
    except Exception as e:
        # هذا السطر سيطبع لنا السبب الحقيقي في الـ Logs داخل موقع Render
        print(f"THE REAL ERROR IS: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))