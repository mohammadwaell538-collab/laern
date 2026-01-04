import 'dart:typed_data';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // required for decoding UTF-8 (supports Arabic text)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show ImageFilter; // required for glass blur effect
// Use universal_html to avoid direct dart:html import and deprecation
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

  // Upload & async job state
  double _uploadProgress = 0.0; // 0.0 - 1.0
  bool _isUploading = false;
  bool _useAsync = false; // Toggle to use /analyze_async
  String? _jobId;
  String _jobStatus = '';
  Timer? _pollingTimer;

  // Server-provided note and fallback flag (used to show modern UI banner)
  String _serverNote = '';
  bool _fallback = false;

  // UI state: selected analysis key (concepts/questions/mindmap/summary)
  String _selectedTypeKey = 'summary';

  // Language is stored in parent widget; create a local getter
  String get _language => widget.language;

  // Simple translation map
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
      'download_success': 'تم تنزيل النتائج (تجريبي).',
      'waiting_for_data': 'بانتظار البيانات للتحليل...',
      'dashboard': 'لوحة القيادة',
      'status': 'حالة التحليل',
      'local': 'محلي',
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
      'download_success': 'Downloaded results (experimental).',
      'waiting_for_data': 'Waiting for data...',
      'dashboard': 'Dashboard',
      'status': 'Analysis Status',
      'local': 'Local',
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

  // Analyze with an optional type (purpose). Buttons will call this with a specific type.
  Future<void> _analyze({String? typeKey}) async {
    final effectiveKey = typeKey ?? _selectedTypeKey;

    // If async mode is enabled, delegate to the async flow that returns job_id and polls
    if (_useAsync) {
      return _analyzeAsync(typeKey: effectiveKey);
    }

    setState(() {
      _isLoading = true;
      _result = '';
      _selectedTypeKey = effectiveKey;
    });

    try {
      final uri = Uri.parse('http://localhost:8080/analyze');
      final request = http.MultipartRequest('POST', uri);

      // إرسال الحقول النصية
      request.fields['text'] = _textController.text;
      request.fields['youtube'] = _youtubeController.text;
      // analysis_type is a concise key understood by the backend
      request.fields['analysis_type'] = effectiveKey; // concepts/questions/mindmap/summary

      // إرسال الملف إذا وجد
      if (_pickedFileBytes != null && _pickedFileName != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            _pickedFileBytes!,
            filename: _pickedFileName!,
          ),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      // If the widget was disposed while awaiting, abandon further UI updates
      if (!mounted) return;

      if (response.statusCode == 200) {
        // فك تشفير البيانات لدعم اللغة العربية بشكل صحيح
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _result = data['analysis'] ?? 'لم يتم العثور على تحليل في الرد.';
          _mainTopics = data['main_topics'] ?? 0;
          _keyPoints = data['key_points'] ?? 0;
          _serverNote = data['note'] ?? '';
          _fallback = data['fallback'] ?? false;
          _interactiveQuestions = (data['interactive_questions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          _sources = (data['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        });
        // Display a user-facing note if the server included one (e.g., fallback notice)
        if (_serverNote.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_serverNote)));
        }
      } else {
        setState(() {
          _result = 'خطأ من السيرفر: ${response.statusCode}';
          _mainTopics = 0;
          _keyPoints = 0;
        });
      }
    } catch (e) {
      setState(() {
        _result = 'فشل الاتصال بالسيرفر. تأكد من تشغيل proxy_server.py\nخطأ: $e';
        _mainTopics = 0;
        _keyPoints = 0;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Async analyze: upload file (shows progress) then poll job status until complete
  Future<void> _analyzeAsync({String? typeKey}) async {
    final effectiveKey = typeKey ?? _selectedTypeKey;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _jobId = null;
      _jobStatus = 'queued';
      _result = '';
      _selectedTypeKey = effectiveKey;
    });

    try {
      // Use browser XHR for web to get upload progress events
      if (kIsWeb) {
        final uri = 'http://localhost:8080/analyze_async';
        final form = html.FormData();
        form.append('text', _textController.text);
        form.append('youtube', _youtubeController.text);
        form.append('analysis_type', effectiveKey);
        if (_pickedFileBytes != null && _pickedFileName != null) {
          final blob = html.Blob([_pickedFileBytes!]);
          form.appendBlob('file', blob, _pickedFileName);
        }

        final xhr = html.HttpRequest();
        xhr.open('POST', uri);
        xhr.upload.onProgress.listen((event) {
          if (event.total != null && event.total! > 0) {
            setState(() {
              _uploadProgress = event.loaded! / event.total!;
            });
          }
        });
        xhr.onLoad.listen((_) async {
          setState(() {
            _uploadProgress = 1.0;
          });
          if (xhr.status == 200 || xhr.status == 202) {
            try {
              final data = json.decode(xhr.responseText!);
              final jobId = data['job_id'] ?? data['id'] ?? null;
              if (jobId != null) {
                _startPollingJob(jobId.toString());
              } else {
                // If server returned immediate result
                setState(() {
                  _result = data['analysis'] ?? '';
                  _interactiveQuestions = (data['interactive_questions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
                  _sources = (data['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
                });
              }
            } catch (e) {
              setState(() {
                _result = 'فشل تفسير رد السيرفر: $e';
              });
            }
          } else {
            setState(() {
              _result = 'خطأ من السيرفر: ${xhr.status}';
            });
          }
          setState(() {
            _isUploading = false;
          });
        });
        xhr.onError.listen((_) {
          setState(() {
            _isUploading = false;
            _result = 'فشل أثناء رفع الملف.';
          });
        });
        xhr.send(form);
        return;
      }

      // Non-web fallback (http.MultipartRequest) - no fine-grained progress available
      final uri = Uri.parse('http://localhost:8080/analyze_async');
      final request = http.MultipartRequest('POST', uri);
      request.fields['text'] = _textController.text;
      request.fields['youtube'] = _youtubeController.text;
      request.fields['analysis_type'] = effectiveKey;
      if (_pickedFileBytes != null && _pickedFileName != null) {
        request.files.add(
          http.MultipartFile.fromBytes('file', _pickedFileBytes!, filename: _pickedFileName!),
        );
      }

      // Show indeterminate progress spinner while uploading
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 || response.statusCode == 202) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final jobId = data['job_id'] ?? data['id'] ?? null;
        if (jobId != null) {
          _startPollingJob(jobId.toString());
        } else {
          setState(() {
            _result = data['analysis'] ?? '';
            _interactiveQuestions = (data['interactive_questions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
            _sources = (data['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          });
        }
      } else {
        setState(() {
          _result = 'خطأ من السيرفر: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _result = 'فشل الاتصال بالسيرفر أثناء التحليل غير المتزامن: $e';
      });
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
    }
  }

  // Polling utilities
  void _startPollingJob(String jobId) {
    _stopPollingJob();
    setState(() {
      _jobId = jobId;
      _jobStatus = 'queued';
    });
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _getJobStatus();
    });
  }

  void _stopPollingJob() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    setState(() {
      _jobId = null;
      _jobStatus = '';
    });
  }

  Future<void> _getJobStatus() async {
    if (_jobId == null) return;
    try {
      final uri = Uri.parse('http://localhost:8080/job/$_jobId/status');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes));
        setState(() {
          _jobStatus = data['status'] ?? _jobStatus;
        });
        if (_jobStatus == 'complete' || _jobStatus == 'finished' || _jobStatus == 'done') {
          // Fetch result and stop polling
          final resUri = Uri.parse('http://localhost:8080/job/$_jobId/result');
          final r = await http.get(resUri);
          if (r.statusCode == 200) {
            final d = json.decode(utf8.decode(r.bodyBytes));
            setState(() {
              _result = d['analysis'] ?? _result;
              _interactiveQuestions = (d['interactive_questions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? _interactiveQuestions;
              _sources = (d['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? _sources;
            });
          }
          _stopPollingJob();
        }
      }
    } catch (e) {
      // swallow to avoid noisy polling errors, show once
      debugPrint('Polling error: $e');
    }
  }

  // Save results locally (experimental). On web, trigger a download; on other platforms, show a snackbar.
  void _saveResults() {
    if (_result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_language=='ar'? 'لا توجد نتائج للحفظ.' : 'No results to save.')));
      return;
    }

    if (kIsWeb) {
      try {
        final bytes = utf8.encode(_result);
        final base64Data = base64Encode(bytes);
        // Trigger download directly without storing the AnchorElement to avoid an unused-variable lint
        html.AnchorElement(href: 'data:application/octet-stream;charset=utf-8;base64,$base64Data')..setAttribute('download', 'analysis.txt')..click();

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('download_success'))));
        return;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((_language=='ar'? 'فشل تنزيل الملف: ' : 'Failed to download file: ')+e.toString())));
        return;
      }
    }

    // Non-web fallback: notify user
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_language=='ar'? 'حفظ محلي غير مدعوم إلا على الويب حالياً.' : 'Local save unsupported on non-web at the moment.')));
  }

  Widget _buildActionButton(String labelKey, IconData icon) {
    final String label = t(labelKey);
    final bool selected = _selectedTypeKey == labelKey;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedTypeKey = labelKey;
        });
        _analyze(typeKey: labelKey);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.deepPurple : Colors.white,
        foregroundColor: selected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: selected ? 6 : 2,
        side: BorderSide(color: selected ? Colors.transparent : Colors.deepPurple.withAlpha((0.12 * 255).round())),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox.shrink(),
            Text(t('app_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              IconButton(
                tooltip: t('dashboard'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DashboardPage(
                        analysis: _result,
                        mainTopics: _mainTopics,
                        keyPoints: _keyPoints,
                        fallback: _fallback,
                        note: _serverNote,
                        language: _language,                      interactiveQuestions: _interactiveQuestions,
                      sources: _sources,                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.dashboard),
              ),
              // Language selector
              PopupMenuButton<String>(
                onSelected: (val) => widget.onLanguageChanged(val),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'ar', child: Text('العربية')),
                  const PopupMenuItem(value: 'en', child: Text('English')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(_language.toUpperCase()),
                ),
              ),
              IconButton(
                tooltip: widget.themeMode == ThemeMode.light ? 'Dark mode' : 'Light mode',
                onPressed: widget.onToggleTheme,
                icon: Icon(widget.themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
              ),
            ],),
          ],
        ),
        centerTitle: true,
        // apply a subtle dark-indigo gradient to appbar background
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveResults,
        icon: const Icon(Icons.save),
        label: Text(t('save_results')),
      ),
      body: Directionality(
        textDirection: _language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modern container for text input
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [Colors.deepPurple.shade50, Colors.deepPurple.shade100]),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('input_text'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _textController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'أدخل نصاً تعليمياً لتحليله...',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Modern YouTube container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade100]),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('youtube_link'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _youtubeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'ضع رابط الفيديو هنا...',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Modern file container (with upload progress)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade50]),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.attach_file, color: Colors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_pickedFileName ?? t('choose_file')),
                        ),
                        ElevatedButton(
                          onPressed: _pickPdf,
                          child: Text(t('choose_file')),
                        ),
                        if (_pickedFileName != null)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _pickedFileBytes = null;
                                _pickedFileName = null;
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isUploading)
                      Column(
                        children: [
                          LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_uploadProgress > 0 ? '${(_uploadProgress * 100).toStringAsFixed(0)}%' : t('waiting_for_data')),
                              TextButton(
                                onPressed: _stopPollingJob,
                                child: const Text('Cancel'),
                              )
                            ],
                          )
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Async toggle and action buttons row
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.settings_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Text('Async'),
                        const SizedBox(width: 6),
                        Switch(
                          value: _useAsync,
                          onChanged: (v) => setState(() => _useAsync = v),
                        ),
                      ],
                    ),
                  ),
                  if (_jobId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.play_circle, color: Colors.blue),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Job: $_jobId', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('Status: $_jobStatus'),
                            ],
                          ),
                          const SizedBox(width: 8),
                          IconButton(onPressed: _stopPollingJob, icon: const Icon(Icons.cancel, color: Colors.red)),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // Action buttons row: 4 targets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: _buildActionButton('extract_concepts', Icons.extension)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildActionButton('generate_questions', Icons.quiz)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildActionButton('mindmap', Icons.account_tree)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildActionButton('summary', Icons.description)),
                ],
              ),

              const SizedBox(height: 16),

              // Primary analyze button
              ElevatedButton.icon(
                onPressed: (_isLoading || _isUploading) ? null : () => _analyze(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  backgroundColor: Colors.blue, // more professional blue
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.auto_awesome),
                label: Text(t('start_analysis'), style: const TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 12),

              // Show a small status indicator if polling
              if (_jobId != null)
                Row(
                  children: [
                    const Icon(Icons.timelapse, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Job $_jobId — $_jobStatus')),
                    TextButton(onPressed: _stopPollingJob, child: const Text('Stop')),
                  ],
                ),

              const SizedBox(height: 18),

              const SizedBox(height: 18),

              // Server note banner (modern design)
              if (_serverNote.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: _fallback ? [Colors.orange, Colors.deepOrange] : [Colors.indigo, Colors.blue]),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      Icon(_fallback ? Icons.error_outline : Icons.info_outline, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_serverNote, style: const TextStyle(color: Colors.white))),
                      if (_fallback)
                        TextButton(
                          onPressed: () {
                            // Future: show details or re-run with a local analyzer
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_language=='ar'?'تحليل محلي: عرض التفاصيل':'Local analysis: show details')));
                          },
                          child: Text(_language=='ar'?'تفاصيل':'Details', style: const TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                ),

              Text(t('results'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade50]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 6))],
                    border: Border.all(color: Colors.deepPurple.withAlpha((0.06 * 255).round())),
                  ),
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        child: SelectableText(
                          _result.isEmpty ? t('waiting_for_data') : _result,
                          style: const TextStyle(fontSize: 15, height: 1.6),
                        ),
                      ),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------- DashboardPage (Glassmorphic) ---------------------
class DashboardPage extends StatelessWidget {
  final String analysis;
  final int mainTopics;
  final int keyPoints;
  final bool fallback;
  final String note;
  final String language;

  const DashboardPage({
    Key? key,
    this.analysis = 'بانتظار البيانات للتحليل...',
    this.mainTopics = 0,
    this.keyPoints = 0,
    this.fallback = false,
    this.note = '',
    this.language = 'ar',
    this.interactiveQuestions = const [],
    this.sources = const [],
  }) : super(key: key);

  final List<Map<String, dynamic>> interactiveQuestions;
  final List<Map<String, dynamic>> sources;

  String t(String key) {
    const Map<String, Map<String, String>> tr = {
      'ar': {
        'main_topics': 'المواضيع الرئيسية',
        'key_points': 'النقاط الأساسية',
        'status': 'حالة التحليل',
        'local': 'محلي',
        'waiting': 'قيد الانتظار',
        'completed': 'مكتمل',
        'questions': 'أسئلة تفاعلية',
        'source': 'المصدر',
      },
      'en': {
        'main_topics': 'Main Topics',
        'key_points': 'Key Points',
        'status': 'Analysis Status',
        'local': 'Local',
        'waiting': 'Waiting',
        'completed': 'Completed',
        'questions': 'Interactive Questions',
        'source': 'Source',
      }
    };
    return tr[language]?[key] ?? key;
  }

  Widget _summaryCard(String title, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha((0.9 * 255).round()),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة القيادة', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top summary cards row with dynamic data
              Row(
                children: [
                  _summaryCard(t('main_topics'), mainTopics.toString()),
                  _summaryCard(t('key_points'), keyPoints.toString()),
                  _summaryCard(t('status'), fallback ? t('local') : (analysis.isEmpty ? t('waiting') : t('completed'))),
                ],
              ),
              const SizedBox(height: 16),

              // glassy section with headings and main content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // small headings list
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.35 * 255).round()),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha((0.25 * 255).round())),
                        ),
                        child: const Column(
                          children: [
                            ListTile(leading: Icon(Icons.topic), title: Text('المواضيع الرئيسية')),
                            ListTile(leading: Icon(Icons.list_alt), title: Text('النقاط الأساسية')),
                            ListTile(leading: Icon(Icons.search), title: Text('مجالات التركيز')),
                          ],
                        ),
                      ),

                      // Main content card (Result)
                      Container(
                        height: 360,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((0.9 * 255).round()),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 8))],
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(t('analysis_result'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      Row(
                                        children: [
                                          IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
                                          IconButton(onPressed: () {}, icon: const Icon(Icons.download)),
                                          IconButton(onPressed: () {}, icon: const Icon(Icons.save)),
                                        ],
                                      )
                                    ],
                                  ),
                                  const Divider(),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha((0.8 * 255).round()),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: SingleChildScrollView(
                                        child: SelectableText(
                                          analysis.isEmpty ? (language=='ar'?'بانتظار البيانات للتحليل...':'Waiting for data...') : analysis,
                                          style: const TextStyle(height: 1.6),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Floating action inside the card (bottom-left)
                            Positioned(
                              left: 16,
                              bottom: 16,
                              child: FloatingActionButton.extended(
                                onPressed: () {},
                                label: const Text('انتقال جديد'),
                                icon: const Icon(Icons.navigation),
                                backgroundColor: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Interactive questions section
                      if (interactiveQuestions.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.95 * 255).round()),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(t('questions'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...interactiveQuestions.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final q = entry.value;
                                final options = List<String>.from(q['options'] ?? []);
                                return ExpansionTile(
                                  title: Text('${idx + 1}. ${q['question'] ?? ''}'),
                                  subtitle: Text('${t('source')}: ${q['source'] ?? ''}'),
                                  children: [
                                    for (var i = 0; i < options.length; i++)
                                      ListTile(
                                        title: Text(options[i]),
                                        trailing: (q['answer_index'] ?? -1) == i ? const Icon(Icons.check, color: Colors.green) : null,
                                      ),
                                    if ((q['answer_index'] ?? -1) >= 0)
                                      Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text('Answer: ${options.isNotEmpty ? options[q['answer_index']] : '—'}'),
                                      ),
                                    TextButton(
                                      onPressed: () {
                                        final sourceId = q['source'];
                                        final src = sources.firstWhere((s) => s['source'] == sourceId, orElse: () => {});
                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: Text(t('source')),
                                            content: Text((src['snippet'] ?? '') as String),
                                            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
                                          ),
                                        );
                                      },
                                      child: Text(t('source')),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ],
                          ),
                        ),

                      // Glass-like footer or additional content
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha((0.15 * 255).round()),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withAlpha((0.12 * 255).round())),
                            ),
                            child: const Text('نمط زجاجي عصري — معلومات إضافية أو تحكمات هنا', textAlign: TextAlign.center),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}