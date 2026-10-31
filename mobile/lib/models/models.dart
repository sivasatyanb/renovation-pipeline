import 'dart:convert';

/// Client location containing city and country.
class ClientLocation {
  final String city;
  final String country;

  ClientLocation({
    required this.city,
    required this.country,
  });

  ClientLocation copyWith({
    String? city,
    String? country,
  }) {
    return ClientLocation(
      city: city ?? this.city,
      country: country ?? this.country,
    );
  }

  factory ClientLocation.fromJson(Map<String, dynamic> json) {
    return ClientLocation(
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'city': city,
      'country': country,
    };
  }
}

/// Room information.
class RoomInfo {
  final String type;
  final num surfaceM2;
  final String confidence;

  RoomInfo({
    required this.type,
    required this.surfaceM2,
    required this.confidence,
  });

  RoomInfo copyWith({
    String? type,
    num? surfaceM2,
    String? confidence,
  }) {
    return RoomInfo(
      type: type ?? this.type,
      surfaceM2: surfaceM2 ?? this.surfaceM2,
      confidence: confidence ?? this.confidence,
    );
  }

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      type: json['type'] as String? ?? '',
      surfaceM2: json['surface_m2'] as num? ?? 0,
      confidence: json['confidence'] as String? ?? 'low',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'surface_m2': surfaceM2,
      'confidence': confidence,
    };
  }
}

/// A work item within a project.
class WorkItem {
  final String trade;
  final String description;
  final num quantity;
  final String unit;

  WorkItem({
    required this.trade,
    required this.description,
    required this.quantity,
    required this.unit,
  });

  factory WorkItem.fromJson(Map<String, dynamic> json) {
    return WorkItem(
      trade: json['trade'] as String? ?? '',
      description: json['description'] as String? ?? '',
      quantity: json['quantity'] as num? ?? 0,
      unit: json['unit'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trade': trade,
      'description': description,
      'quantity': quantity,
      'unit': unit,
    };
  }
}

/// The renovation project description.
class Project {
  final String projectId;
  final ClientLocation client;
  final RoomInfo room;
  final String style;
  final List<String> renderUrls;
  final List<WorkItem> workItems;

  Project({
    required this.projectId,
    required this.client,
    required this.room,
    required this.style,
    required this.renderUrls,
    required this.workItems,
  });

  Project copyWith({
    String? projectId,
    ClientLocation? client,
    RoomInfo? room,
    String? style,
    List<String>? renderUrls,
    List<WorkItem>? workItems,
  }) {
    return Project(
      projectId: projectId ?? this.projectId,
      client: client ?? this.client,
      room: room ?? this.room,
      style: style ?? this.style,
      renderUrls: renderUrls ?? this.renderUrls,
      workItems: workItems ?? this.workItems,
    );
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      projectId: json['project_id'] as String? ?? '',
      client: ClientLocation.fromJson(
        (json['client'] as Map<String, dynamic>?) ?? {},
      ),
      room: RoomInfo.fromJson(
        (json['room'] as Map<String, dynamic>?) ?? {},
      ),
      style: json['style'] as String? ?? '',
      renderUrls: (json['render_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      workItems: (json['work_items'] as List<dynamic>?)
              ?.map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'project_id': projectId,
      'client': client.toJson(),
      'room': room.toJson(),
      'style': style,
      'render_urls': renderUrls,
      'work_items': workItems.map((e) => e.toJson()).toList(),
    };
  }
}

/// Currency information.
class CurrencyInfo {
  final String code;
  final String symbol;

  CurrencyInfo({
    required this.code,
    required this.symbol,
  });

  factory CurrencyInfo.fromJson(Map<String, dynamic> json) {
    return CurrencyInfo(
      code: json['code'] as String? ?? 'EUR',
      symbol: json['symbol'] as String? ?? '€',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'symbol': symbol,
    };
  }
}

/// Option for a quiz question.
class QuizOption {
  final String value;
  final String labelTemplate;

  QuizOption({
    required this.value,
    required this.labelTemplate,
  });

  String getFormattedLabel(String currencySymbol) {
    return labelTemplate.replaceAll('{currency}', currencySymbol);
  }

  factory QuizOption.fromJson(Map<String, dynamic> json) {
    return QuizOption(
      value: json['value'] as String? ?? '',
      labelTemplate: json['label_template'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'label_template': labelTemplate,
    };
  }
}

/// Quiz question definition.
class QuizQuestion {
  final String id;
  final String question;
  final String type;
  final int minSelections;
  final bool usesCurrencySymbol;
  final List<QuizOption> options;

  QuizQuestion({
    required this.id,
    required this.question,
    required this.type,
    this.minSelections = 1,
    required this.usesCurrencySymbol,
    required this.options,
  });

  bool get isMultiSelect => type == 'multi_select';

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      type: json['type'] as String? ?? 'single_choice',
      minSelections: json['min_selections'] as int? ?? 1,
      usesCurrencySymbol: json['uses_currency_symbol'] as bool? ?? false,
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => QuizOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'type': type,
      'min_selections': minSelections,
      'uses_currency_symbol': usesCurrencySymbol,
      'options': options.map((e) => e.toJson()).toList(),
    };
  }
}

/// Quiz configuration parsed from quiz_questions.json.
class QuizConfig {
  final Map<String, CurrencyInfo> currencyByCountry;
  final List<QuizQuestion> questions;

  QuizConfig({
    required this.currencyByCountry,
    required this.questions,
  });

  CurrencyInfo getCurrency(String? country) {
    if (country != null && currencyByCountry.containsKey(country)) {
      return currencyByCountry[country]!;
    }
    return currencyByCountry['default'] ??
        CurrencyInfo(code: 'EUR', symbol: '€');
  }

  factory QuizConfig.fromJson(Map<String, dynamic> json) {
    final currencyMap = <String, CurrencyInfo>{};
    if (json['currency_by_country'] is Map<String, dynamic>) {
      (json['currency_by_country'] as Map<String, dynamic>)
          .forEach((key, val) {
        if (val is Map<String, dynamic>) {
          currencyMap[key] = CurrencyInfo.fromJson(val);
        }
      });
    }

    final questionsList = <QuizQuestion>[];
    if (json['questions'] is List<dynamic>) {
      for (final item in json['questions'] as List<dynamic>) {
        if (item is Map<String, dynamic>) {
          questionsList.add(QuizQuestion.fromJson(item));
        }
      }
    }

    return QuizConfig(
      currencyByCountry: currencyMap,
      questions: questionsList,
    );
  }

  factory QuizConfig.fromRawJson(String rawJson) =>
      QuizConfig.fromJson(json.decode(rawJson) as Map<String, dynamic>);
}

/// User answers submitted to the backend.
class QuizAnswers {
  final String budget;
  final String scope;
  final String timeline;
  final String priority;
  final List<String> trustRequirements;

  QuizAnswers({
    required this.budget,
    required this.scope,
    required this.timeline,
    required this.priority,
    required this.trustRequirements,
  });

  factory QuizAnswers.fromJson(Map<String, dynamic> json) {
    return QuizAnswers(
      budget: json['budget'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      timeline: json['timeline'] as String? ?? '',
      priority: json['priority'] as String? ?? '',
      trustRequirements: (json['trust_requirements'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'budget': budget,
      'scope': scope,
      'timeline': timeline,
      'priority': priority,
      'trust_requirements': trustRequirements,
    };
  }
}

/// Line item in a price estimate.
class PriceLineItem {
  final String label;
  final num? low;
  final num? high;

  PriceLineItem({
    required this.label,
    this.low,
    this.high,
  });

  factory PriceLineItem.fromJson(Map<String, dynamic> json) {
    return PriceLineItem(
      label: json['label'] as String? ?? '',
      low: json['low'] as num?,
      high: json['high'] as num?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'low': low,
      'high': high,
    };
  }
}

/// Price estimate object.
class PriceEstimate {
  final num? low;
  final num? high;
  final String currency;
  final List<PriceLineItem> lineItems;
  final List<String> sourceUrls;

  PriceEstimate({
    this.low,
    this.high,
    required this.currency,
    required this.lineItems,
    required this.sourceUrls,
  });

  factory PriceEstimate.fromJson(Map<String, dynamic> json) {
    return PriceEstimate(
      low: json['low'] as num?,
      high: json['high'] as num?,
      currency: json['currency'] as String? ?? 'EUR',
      lineItems: (json['line_items'] as List<dynamic>?)
              ?.map((e) => PriceLineItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      sourceUrls: (json['source_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'low': low,
      'high': high,
      'currency': currency,
      'line_items': lineItems.map((e) => e.toJson()).toList(),
      'source_urls': sourceUrls,
    };
  }
}

/// Expected price range for a contractor.
class ExpectedPrice {
  final num? low;
  final num? high;
  final String currency;

  ExpectedPrice({
    this.low,
    this.high,
    required this.currency,
  });

  factory ExpectedPrice.fromJson(Map<String, dynamic> json) {
    return ExpectedPrice(
      low: json['low'] as num?,
      high: json['high'] as num?,
      currency: json['currency'] as String? ?? 'EUR',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'low': low,
      'high': high,
      'currency': currency,
    };
  }
}

/// Certification entry.
class Certification {
  final String name;
  final String? sourceUrl;

  Certification({
    required this.name,
    this.sourceUrl,
  });

  factory Certification.fromJson(Map<String, dynamic> json) {
    return Certification(
      name: json['name'] as String? ?? '',
      sourceUrl: json['source_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'source_url': sourceUrl,
    };
  }
}

/// Subscores breakdown.
class Subscores {
  final num price;
  final num reputation;
  final num fit;
  final num availability;

  Subscores({
    required this.price,
    required this.reputation,
    required this.fit,
    required this.availability,
  });

  factory Subscores.fromJson(Map<String, dynamic> json) {
    return Subscores(
      price: json['price'] as num? ?? 0,
      reputation: json['reputation'] as num? ?? 0,
      fit: json['fit'] as num? ?? 0,
      availability: json['availability'] as num? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'price': price,
      'reputation': reputation,
      'fit': fit,
      'availability': availability,
    };
  }
}

/// Call brief for bargaining / inquiries.
class CallBrief {
  final num? targetPrice;
  final num? maxPrice;
  final List<String> leveragePoints;
  final List<String> questionsToAsk;

  CallBrief({
    this.targetPrice,
    this.maxPrice,
    required this.leveragePoints,
    required this.questionsToAsk,
  });

  factory CallBrief.fromJson(Map<String, dynamic> json) {
    return CallBrief(
      targetPrice: json['target_price'] as num?,
      maxPrice: json['max_price'] as num?,
      leveragePoints: (json['leverage_points'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      questionsToAsk: (json['questions_to_ask'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'target_price': targetPrice,
      'max_price': maxPrice,
      'leverage_points': leveragePoints,
      'questions_to_ask': questionsToAsk,
    };
  }
}

/// Contractor profile.
class Contractor {
  final String id;
  final int rank;
  final String name;
  final String phoneE164;
  final bool phoneVerified;
  final String? phoneSourceUrl;
  final String? website;
  final String? address;
  final List<String> trades;
  final num? rating;
  final int? reviewCount;
  final List<Certification> certifications;
  final String? insurance;
  final List<String> portfolioUrls;
  final ExpectedPrice? expectedPrice;
  final String? availability;
  final num score;
  final Subscores subscores;
  final String whyRecommended;
  final List<String> redFlags;
  final List<String> sourceUrls;
  final CallBrief? callBrief;

  Contractor({
    required this.id,
    required this.rank,
    required this.name,
    required this.phoneE164,
    required this.phoneVerified,
    this.phoneSourceUrl,
    this.website,
    this.address,
    required this.trades,
    this.rating,
    this.reviewCount,
    required this.certifications,
    this.insurance,
    required this.portfolioUrls,
    this.expectedPrice,
    this.availability,
    required this.score,
    required this.subscores,
    required this.whyRecommended,
    required this.redFlags,
    required this.sourceUrls,
    this.callBrief,
  });

  factory Contractor.fromJson(Map<String, dynamic> json) {
    return Contractor(
      id: json['id'] as String? ?? '',
      rank: json['rank'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      phoneE164: json['phone_e164'] as String? ?? '',
      phoneVerified: json['phone_verified'] as bool? ?? false,
      phoneSourceUrl: json['phone_source_url'] as String?,
      website: json['website'] as String?,
      address: json['address'] as String?,
      trades: (json['trades'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      rating: json['rating'] as num?,
      reviewCount: json['review_count'] as int?,
      certifications: (json['certifications'] as List<dynamic>?)
              ?.map((e) => Certification.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      insurance: json['insurance'] as String?,
      portfolioUrls: (json['portfolio_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      expectedPrice: json['expected_price'] != null
          ? ExpectedPrice.fromJson(
              json['expected_price'] as Map<String, dynamic>)
          : null,
      availability: json['availability'] as String?,
      score: json['score'] as num? ?? 0,
      subscores: Subscores.fromJson(
        (json['subscores'] as Map<String, dynamic>?) ?? {},
      ),
      whyRecommended: json['why_recommended'] as String? ?? '',
      redFlags: (json['red_flags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sourceUrls: (json['source_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      callBrief: json['call_brief'] != null
          ? CallBrief.fromJson(json['call_brief'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rank': rank,
      'name': name,
      'phone_e164': phoneE164,
      'phone_verified': phoneVerified,
      'phone_source_url': phoneSourceUrl,
      'website': website,
      'address': address,
      'trades': trades,
      'rating': rating,
      'review_count': reviewCount,
      'certifications': certifications.map((e) => e.toJson()).toList(),
      'insurance': insurance,
      'portfolio_urls': portfolioUrls,
      'expected_price': expectedPrice?.toJson(),
      'availability': availability,
      'score': score,
      'subscores': subscores.toJson(),
      'why_recommended': whyRecommended,
      'red_flags': redFlags,
      'source_urls': sourceUrls,
      'call_brief': callBrief?.toJson(),
    };
  }
}

/// Research result model.
class ResearchResult {
  final String projectId;
  final bool isDemo;
  final PriceEstimate priceEstimate;
  final List<Contractor> contractors;
  final List<String> warnings;

  ResearchResult({
    required this.projectId,
    this.isDemo = false,
    required this.priceEstimate,
    required this.contractors,
    required this.warnings,
  });

  factory ResearchResult.fromJson(Map<String, dynamic> json) {
    return ResearchResult(
      projectId: json['project_id'] as String? ?? '',
      isDemo: json['is_demo'] as bool? ?? false,
      priceEstimate: PriceEstimate.fromJson(
        (json['price_estimate'] as Map<String, dynamic>?) ?? {},
      ),
      contractors: (json['contractors'] as List<dynamic>?)
              ?.map((e) => Contractor.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'project_id': projectId,
      'is_demo': isDemo,
      'price_estimate': priceEstimate.toJson(),
      'contractors': contractors.map((e) => e.toJson()).toList(),
      'warnings': warnings,
    };
  }
}

/// Job status response from GET /research/{job_id}.
class JobStatusResponse {
  final String status;
  final String phase;
  final ResearchResult? result;
  final String? error;

  JobStatusResponse({
    required this.status,
    required this.phase,
    this.result,
    this.error,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  factory JobStatusResponse.fromJson(Map<String, dynamic> json) {
    return JobStatusResponse(
      status: json['status'] as String? ?? '',
      phase: json['phase'] as String? ?? '',
      result: json['result'] != null
          ? ResearchResult.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'phase': phase,
      'result': result?.toJson(),
      'error': error,
    };
  }
}


/// Meeting request details inside CallRequest.
class MeetingRequest {
  final String customerEmail;
  final String address;
  final List<String> slots;

  MeetingRequest({
    required this.customerEmail,
    required this.address,
    this.slots = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'customer_email': customerEmail,
      'address': address,
      'slots': slots,
    };
  }
}

/// Call request payload for starting a simulated negotiation call.
class CallRequest {
  final String jobId;
  final String contractorId;
  final MeetingRequest meeting;

  CallRequest({
    required this.jobId,
    required this.contractorId,
    required this.meeting,
  });

  Map<String, dynamic> toJson() {
    return {
      'job_id': jobId,
      'contractor_id': contractorId,
      'meeting': meeting.toJson(),
    };
  }
}

/// A single turn in a call transcript.
class CallTurn {
  final int index;
  final String speaker; // 'customer_agent' | 'renovator_agent'
  final String text;
  final String? audioUrl;

  CallTurn({
    required this.index,
    required this.speaker,
    required this.text,
    this.audioUrl,
  });

  factory CallTurn.fromJson(Map<String, dynamic> json) {
    return CallTurn(
      index: json['index'] as int? ?? 0,
      speaker: json['speaker'] as String? ?? '',
      text: json['text'] as String? ?? '',
      audioUrl: json['audio_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'speaker': speaker,
      'text': text,
      'audio_url': audioUrl,
    };
  }
}

/// Outcome extracted and computed at the end of a call.
class CallOutcome {
  final String endReason;
  final num? openingPrice;
  final num? finalPrice;
  final num? savings;
  final String? currency;
  final bool? labourIncluded;
  final bool? materialsIncluded;
  final bool? taxIncluded;
  final bool? scopeConfirmed;
  final String? agreedSlot;
  final String? notes;

  CallOutcome({
    required this.endReason,
    this.openingPrice,
    this.finalPrice,
    this.savings,
    this.currency,
    this.labourIncluded,
    this.materialsIncluded,
    this.taxIncluded,
    this.scopeConfirmed,
    this.agreedSlot,
    this.notes,
  });

  factory CallOutcome.fromJson(Map<String, dynamic> json) {
    return CallOutcome(
      endReason: json['end_reason'] as String? ?? '',
      openingPrice: json['opening_price'] as num?,
      finalPrice: json['final_price'] as num?,
      savings: json['savings'] as num?,
      currency: json['currency'] as String?,
      labourIncluded: json['labour_included'] as bool?,
      materialsIncluded: json['materials_included'] as bool?,
      taxIncluded: json['tax_included'] as bool?,
      scopeConfirmed: json['scope_confirmed'] as bool?,
      agreedSlot: json['agreed_slot'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'end_reason': endReason,
      'opening_price': openingPrice,
      'final_price': finalPrice,
      'savings': savings,
      'currency': currency,
      'labour_included': labourIncluded,
      'materials_included': materialsIncluded,
      'tax_included': taxIncluded,
      'scope_confirmed': scopeConfirmed,
      'agreed_slot': agreedSlot,
      'notes': notes,
    };
  }
}

/// Match determination for a call.
class CallMatch {
  final bool match;
  final List<String> reasons;

  CallMatch({
    required this.match,
    required this.reasons,
  });

  factory CallMatch.fromJson(Map<String, dynamic> json) {
    return CallMatch(
      match: json['match'] as bool? ?? false,
      reasons: (json['reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'match': match,
      'reasons': reasons,
    };
  }
}

/// In-person meeting booking result.
class CallBooking {
  final String status; // 'created' | 'link_only' | 'failed'
  final String? startsAt;
  final String? location;
  final String? eventUrl;
  final List<String> warnings;

  CallBooking({
    required this.status,
    this.startsAt,
    this.location,
    this.eventUrl,
    required this.warnings,
  });

  factory CallBooking.fromJson(Map<String, dynamic> json) {
    return CallBooking(
      status: json['status'] as String? ?? '',
      startsAt: json['starts_at'] as String?,
      location: json['location'] as String?,
      eventUrl: json['event_url'] as String?,
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'starts_at': startsAt,
      'location': location,
      'event_url': eventUrl,
      'warnings': warnings,
    };
  }
}

/// Overall status of a call session from GET /calls/{call_id}.
class CallStatusResponse {
  final String status; // 'queued' | 'running' | 'completed' | 'failed' | 'stopped'
  final String phase; // 'negotiating' | 'analyzing' | 'scheduling' | 'done'
  final bool simulated;
  final bool isReplay;
  final List<CallTurn> turns;
  final CallOutcome? outcome;
  final CallMatch? match;
  final CallBooking? booking;
  final List<String> warnings;
  final String? error;

  CallStatusResponse({
    required this.status,
    required this.phase,
    this.simulated = true,
    this.isReplay = false,
    required this.turns,
    this.outcome,
    this.match,
    this.booking,
    required this.warnings,
    this.error,
  });

  bool get isTerminal =>
      status == 'completed' || status == 'failed' || status == 'stopped';

  factory CallStatusResponse.fromJson(Map<String, dynamic> json) {
    return CallStatusResponse(
      status: json['status'] as String? ?? '',
      phase: json['phase'] as String? ?? '',
      simulated: json['simulated'] as bool? ?? true,
      isReplay: json['is_replay'] as bool? ?? false,
      turns: (json['turns'] as List<dynamic>?)
              ?.map((e) => CallTurn.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      outcome: json['outcome'] != null
          ? CallOutcome.fromJson(json['outcome'] as Map<String, dynamic>)
          : null,
      match: json['match'] != null
          ? CallMatch.fromJson(json['match'] as Map<String, dynamic>)
          : null,
      booking: json['booking'] != null
          ? CallBooking.fromJson(json['booking'] as Map<String, dynamic>)
          : null,
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'phase': phase,
      'simulated': simulated,
      'is_replay': isReplay,
      'turns': turns.map((e) => e.toJson()).toList(),
      'outcome': outcome?.toJson(),
      'match': match?.toJson(),
      'booking': booking?.toJson(),
      'warnings': warnings,
      'error': error,
    };
  }
}


/// Request payload for creating a renovation render.
class RenderRequest {
  final String imageBase64;
  final String mimeType;
  final String instruction;
  final String? city;
  final String? country;

  RenderRequest({
    required this.imageBase64,
    required this.mimeType,
    required this.instruction,
    this.city,
    this.country,
  });

  Map<String, dynamic> toJson() {
    return {
      'image_base64': imageBase64,
      'mime_type': mimeType,
      'instruction': instruction,
      if (city != null) 'city': city,
      if (country != null) 'country': country,
    };
  }

  factory RenderRequest.fromJson(Map<String, dynamic> json) {
    return RenderRequest(
      imageBase64: json['image_base64'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? 'image/jpeg',
      instruction: json['instruction'] as String? ?? '',
      city: json['city'] as String?,
      country: json['country'] as String?,
    );
  }
}

/// The result of a completed renovation render.
class RenderResult {
  final String beforeUrl;
  final String afterUrl;
  final String renovationPrompt;
  final String voiceConfirmation;
  final String? audioUrl;
  final String modelUsed;
  final int latencyMs;
  final RoomInfo room;
  final String style;
  final List<WorkItem> workItems;

  RenderResult({
    required this.beforeUrl,
    required this.afterUrl,
    required this.renovationPrompt,
    required this.voiceConfirmation,
    this.audioUrl,
    required this.modelUsed,
    required this.latencyMs,
    required this.room,
    required this.style,
    required this.workItems,
  });

  factory RenderResult.fromJson(Map<String, dynamic> json) {
    return RenderResult(
      beforeUrl: json['before_url'] as String? ?? '',
      afterUrl: json['after_url'] as String? ?? '',
      renovationPrompt: json['renovation_prompt'] as String? ?? '',
      voiceConfirmation: json['voice_confirmation'] as String? ?? '',
      audioUrl: json['audio_url'] as String?,
      modelUsed: json['model_used'] as String? ?? '',
      latencyMs: json['latency_ms'] as int? ?? 0,
      room: RoomInfo.fromJson((json['room'] as Map<String, dynamic>?) ?? {}),
      style: json['style'] as String? ?? '',
      workItems: (json['work_items'] as List<dynamic>?)
              ?.map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'before_url': beforeUrl,
      'after_url': afterUrl,
      'renovation_prompt': renovationPrompt,
      'voice_confirmation': voiceConfirmation,
      'audio_url': audioUrl,
      'model_used': modelUsed,
      'latency_ms': latencyMs,
      'room': room.toJson(),
      'style': style,
      'work_items': workItems.map((e) => e.toJson()).toList(),
    };
  }

  Project toProject({
    required String city,
    String country = 'France',
    required String baseUrl,
  }) {
    final cleanCity = city.trim().isEmpty ? 'Paris' : city.trim();
    final cleanBaseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanAfterUrl = afterUrl.startsWith('/') ? afterUrl : '/$afterUrl';
    final resolvedUrl =
        afterUrl.startsWith('http') ? afterUrl : '$cleanBaseUrl$cleanAfterUrl';

    return Project(
      projectId: 'studio-${DateTime.now().millisecondsSinceEpoch}',
      client: ClientLocation(city: cleanCity, country: country),
      room: room,
      style: style,
      renderUrls: [resolvedUrl],
      workItems: workItems,
    );
  }
}

/// Status of a renovation render job.
class RenderStatusResponse {
  final String status;
  final String? phase;
  final bool isReplay;
  final RenderResult? result;
  final List<String> warnings;
  final String? error;

  RenderStatusResponse({
    required this.status,
    this.phase,
    this.isReplay = false,
    this.result,
    this.warnings = const [],
    this.error,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  factory RenderStatusResponse.fromJson(Map<String, dynamic> json) {
    return RenderStatusResponse(
      status: json['status'] as String? ?? '',
      phase: json['phase'] as String?,
      isReplay: json['is_replay'] as bool? ?? false,
      result: json['result'] != null
          ? RenderResult.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'phase': phase,
      'is_replay': isReplay,
      'result': result?.toJson(),
      'warnings': warnings,
      'error': error,
    };
  }
}
