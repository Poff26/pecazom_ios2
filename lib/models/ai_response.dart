class AIResponse {
  final int chancePercent;
  final String recommendedFish;
  final String recommendedBait;
  final String recommendedTime;
  final String method;
  final String rig;
  final String planB;
  final String reason;
  final List<String> tips;
  final bool aiAvailable;

  AIResponse({
    required this.chancePercent,
    required this.recommendedFish,
    required this.recommendedBait,
    required this.recommendedTime,
    required this.method,
    required this.rig,
    required this.planB,
    required this.reason,
    required this.tips,
    required this.aiAvailable,
  });

  factory AIResponse.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) {
      final v = json[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    String readString(String key, String fallback) {
      final v = json[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return fallback;
    }

    List<String> readTips() {
      final out = <String>[];

      final bait = json['bait_tips'];
      final spot = json['spot_tips'];

      if (bait is List) {
        out.addAll(bait.whereType<String>());
      }
      if (spot is List) {
        out.addAll(spot.whereType<String>());
      }

      return out.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    return AIResponse(
      chancePercent: readInt('chance', 0),
      recommendedFish: readString('recommended_fish', 'Nem ismert'),
      recommendedBait: readString('recommended_bait', 'Nem ismert'),
      recommendedTime: readString('recommended_time', 'Nem ismert'),
      method: readString('method', 'Nem ismert'),
      rig: readString('rig', 'Nem ismert'),
      planB: readString('plan_b', 'Nem ismert'),
      reason: (json['why'] is List && json['why'].isNotEmpty)
          ? (json['why'] as List).first.toString()
          : 'Nincs indoklás.',
      tips: readTips(),
      aiAvailable: json['llm_used'] is bool ? json['llm_used'] as bool : true,
    );
  }
}
