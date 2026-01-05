import 'dart:typed_data';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // required for decoding UTF-8 (supports Arabic text)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show ImageFilter; // required for glass blur effect
import 'package:universal_html/html.dart' as html;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  String _language = 'ar'; // 'ar' or 'en'

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _setLanguage(String lang) {
    setState(() {
      _language = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Laern Analyzer',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      themeMode: _themeMode,
      home: HomePage(
        language: _language,
        onLanguageChanged: _setLanguage,
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String language;
  final void Function(String) onLanguageChanged;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  const HomePage({
    Key? key,
    this.language = 'ar',
    required this.onLanguageChanged,
    this.themeMode = ThemeMode.light,
    required this.onToggleTheme,
  }) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _youtubeController = TextEditingController();

  Uint8List? _pickedFileBytes;
  String? _pickedFileName;
  String _result = '';
  bool _isLoading = false;
  int _mainTopics = 0;
  int _keyPoints = 0;

  List<Map<String, dynamic>> _interactiveQuestions = [];
  List<Map<String, dynamic>> _sources = [];

  double _uploadProgress = 0.0;
  bool _isUploading = false;
  bool _useAsync = false; 
  String? _jobId;
  String _jobStatus = '';
  Timer? _pollingTimer;

  String _serverNote = '';
  bool _fallback = false;
  String _selectedTypeKey = 'summary';

  String get _language => widget.language;

  static const Map<String, Map<String, String>> tr = {
    'ar': {
      'app_title': 'محلل التعليم Laern',
      'input_text': 'نص للإدخال',
      'youtube_link': 'رابط YouTube',
      'choose_file': 'اختيار ملف',
      'extract_concepts': 'استخراج المفاهيم',
      'generate_questions': 'توليد أسئلة',
      'mindmap': 'خريطة ذهنية',
      'summary': 'ملخص شامل',
      'start_analysis': 'ابدأ تحليل الذكاء الاصطناعي',
      'results': 'النتائج والتحليل:',
      'save_results': 'حفظ النتائج',
      'download_success': 'تم تنزيل النتائج.',
      'waiting_for_data': 'بانتظار البيانات للتحليل...',
      'dashboard': 'لوحة القيادة',
      'status': 'حالة التحليل',
    },
    'en': {
      'app_title': 'Laern Analyzer',
      'input_text': 'Input Text',
      'youtube_link': 'YouTube Link',
      'choose_file': 'Choose File',
      'extract_concepts': 'Extract Concepts',
      'generate_questions': 'Generate Questions',
      'mindmap': 'Mind Map',
      'summary': 'Comprehensive Summary',
      'start_analysis': 'Start AI Analysis',
      'results': 'Results & Analysis:',
      'save_results': 'Save Results',
      'download_success': 'Downloaded results.',
      'waiting_for_data': 'Waiting for data...',
      'dashboard': 'Dashboard',
    }
  };

  String t(String key) => tr[_language]?[key] ?? key;

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _pickedFileBytes = result.files.first.bytes;
        _pickedFileName = result.files.first.name;
      });
    }
  }

  // تم تعديل الرابط هنا إلى الإنتاج
  Future<void> _analyze({String? typeKey}) async {
    final effectiveKey = typeKey ?? _selectedTypeKey;
    if (_useAsync) return _analyzeAsync(typeKey: effectiveKey);

    setState(() {
      _isLoading = true;
      _result = '';
      _selectedTypeKey = effectiveKey;
    });

    try {
      final uri = Uri.parse('https://laern.onrender.com/analyze');
      final request = http.MultipartRequest('POST', uri);
      request.fields['text'] = _textController.text;
      request.fields['youtube'] = _youtubeController.text;
      request.fields['analysis_type'] = effectiveKey;

      if (_pickedFileBytes != null && _pickedFileName != null) {
        request.files.add(http.MultipartFile.fromBytes('file', _pickedFileBytes!, filename: _pickedFileName!));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _result = data['analysis'] ?? 'لم يتم العثور على تحليل.';
          _mainTopics = data['main_topics'] ?? 0;
          _keyPoints = data['key_points'] ?? 0;
          _serverNote = data['note'] ?? '';
          _fallback = data['fallback'] ?? false;
          _interactiveQuestions = (data['interactive_questions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          _sources = (data['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        });
      } else {
        setState(() => _result = 'خطأ من السيرفر: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _result = 'فشل الاتصال بالسيرفر. تأكد أن السيرفر يعمل على Render.\nخطأ: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // تم تعديل الرابط هنا أيضاً للرفع غير المتزامن
  Future<void> _analyzeAsync({String? typeKey}) async {
    final effectiveKey = typeKey ?? _selectedTypeKey;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _jobId = null;
      _jobStatus = 'queued';
    });

    try {
      final String baseUrl = 'https://laern.onrender.com/analyze_async';
      if (kIsWeb) {
        final form = html.FormData();
        form.append('text', _textController.text);
        form.append('youtube', _youtubeController.text);
        form.append('analysis_type', effectiveKey);
        if (_pickedFileBytes != null) {
          form.appendBlob('file', html.Blob([_pickedFileBytes!]), _pickedFileName);
        }

        final xhr = html.HttpRequest();
        xhr.open('POST', baseUrl);
        xhr.upload.onProgress.listen((e) {
          if (e.total != null && e.total! > 0) setState(() => _uploadProgress = e.loaded! / e.total!);
        });
        xhr.onLoad.listen((_) {
          if (xhr.status == 200 || xhr.status == 202) {
            final data = json.decode(xhr.responseText!);
            final jobId = data['job_id'] ?? data['id'];
            if (jobId != null) _startPollingJob(jobId.toString());
          }
          setState(() => _isUploading = false);
        });
        xhr.send(form);
      } else {
        final uri = Uri.parse(baseUrl);
        final request = http.MultipartRequest('POST', uri);
        request.fields['text'] = _textController.text;
        request.fields['youtube'] = _youtubeController.text;
        request.fields['analysis_type'] = effectiveKey;
        if (_pickedFileBytes != null) {
          request.files.add(http.MultipartFile.fromBytes('file', _pickedFileBytes!, filename: _pickedFileName!));
        }
        final resp = await http.Response.fromStream(await request.send());
        final data = json.decode(utf8.decode(resp.bodyBytes));
        if (data['job_id'] != null) _startPollingJob(data['job_id'].toString());
        setState(() => _isUploading = false);
      }
    } catch (e) {
      setState(() { _result = 'خطأ: $e'; _isUploading = false; });
    }
  }

  void _startPollingJob(String jobId) {
    _stopPollingJob();
    setState(() { _jobId = jobId; _jobStatus = 'queued'; });
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _getJobStatus());
  }

  void _stopPollingJob() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // تم تعديل روابط التتبع (Polling)
  Future<void> _getJobStatus() async {
    if (_jobId == null) return;
    try {
      final uri = Uri.parse('https://laern.onrender.com/job/$_jobId/status');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes));
        setState(() => _jobStatus = data['status'] ?? _jobStatus);
        
        if (_jobStatus == 'complete' || _jobStatus == 'finished') {
          final resUri = Uri.parse('https://laern.onrender.com/job/$_jobId/result');
          final r = await http.get(resUri);
          final d = json.decode(utf8.decode(r.bodyBytes));
          setState(() => _result = d['analysis'] ?? '');
          _stopPollingJob();
        }
      }
    } catch (e) { debugPrint('Polling error: $e'); }
  }

  void _saveResults() {
    if (_result.isEmpty) return;
    if (kIsWeb) {
      final bytes = utf8.encode(_result);
      final base64Data = base64Encode(bytes);
      html.AnchorElement(href: 'data:application/octet-stream;base64,$base64Data')..setAttribute('download', 'analysis.txt')..click();
    }
  }

  Widget _buildActionButton(String labelKey, IconData icon) {
    final bool selected = _selectedTypeKey == labelKey;
    return ElevatedButton(
      onPressed: () => _analyze(typeKey: labelKey),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue : Colors.white,
        foregroundColor: selected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        children: [Icon(icon, size: 18), Text(t(labelKey), style: const TextStyle(fontSize: 10))],
      ),
    );
  }

  @override
  void dispose() { _pollingTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('app_title')),
        actions: [
          IconButton(onPressed: widget.onToggleTheme, icon: Icon(widget.themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode)),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _saveResults, child: const Icon(Icons.download)),
      body: Directionality(
        textDirection: _language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _textController, maxLines: 3, decoration: InputDecoration(labelText: t('input_text'), border: const OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _youtubeController, decoration: InputDecoration(labelText: t('youtube_link'), prefixIcon: const Icon(Icons.link), border: const OutlineInputBorder())),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton(onPressed: _pickPdf, child: Text(t('choose_file'))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_pickedFileName ?? '')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text("Async Mode"),
                  Switch(value: _useAsync, onChanged: (v) => setState(() => _useAsync = v)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildActionButton('extract_concepts', Icons.lightbulb)),
                  const SizedBox(width: 5),
                  Expanded(child: _buildActionButton('generate_questions', Icons.quiz)),
                  const SizedBox(width: 5),
                  Expanded(child: _buildActionButton('mindmap', Icons.map)),
                  const SizedBox(width: 5),
                  Expanded(child: _buildActionButton('summary', Icons.summarize)),
                ],
              ),
              const SizedBox(height: 15),
              if (_isLoading || _isUploading) const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
                  child: SingleChildScrollView(child: SelectableText(_result.isEmpty ? t('waiting_for_data') : _result)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}