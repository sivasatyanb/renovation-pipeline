"""Pydantic v2 models matching /shared/schemas and Phase 2 LLM extraction contracts."""

from __future__ import annotations

from typing import Any, Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# ---------------------------------------------------------------------------
# Request Schema Models (/shared/schemas/research_request.schema.json)
# ---------------------------------------------------------------------------

RoomConfidence = Literal["low", "medium", "high"]
BudgetOption = Literal["under_5k", "5k_15k", "15k_40k", "over_40k", "unknown"]
ScopeOption = Literal["cosmetic", "partial", "full_nonstructural", "full_structural"]
TimelineOption = Literal[
    "under_one_month",
    "one_to_three_months",
    "three_to_six_months",
    "flexible",
]
PriorityOption = Literal["lowest_price", "balanced", "quality", "design_match"]
TrustRequirementOption = Literal[
    "licensed_insured",
    "high_reviews",
    "style_portfolio",
    "written_quote",
    "single_contact",
]


class ClientInfo(BaseModel):
    model_config = ConfigDict(extra="forbid")

    city: str = Field(..., min_length=1)
    country: str = Field(..., min_length=1)


class RoomInfo(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: str = Field(..., min_length=1)
    surface_m2: float = Field(..., gt=0)
    confidence: RoomConfidence


class WorkItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    trade: str = Field(..., min_length=1)
    description: str = Field(..., min_length=1)
    quantity: float = Field(..., gt=0)
    unit: str = Field(..., min_length=1)


class ProjectInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    project_id: str = Field(..., min_length=1)
    client: ClientInfo
    room: RoomInfo
    style: str = Field(..., min_length=1)
    render_urls: list[str]
    work_items: list[WorkItem] = Field(..., min_length=1)


class QuizAnswers(BaseModel):
    model_config = ConfigDict(extra="forbid")

    budget: BudgetOption
    scope: ScopeOption
    timeline: TimelineOption
    priority: PriorityOption
    trust_requirements: list[TrustRequirementOption] = Field(..., min_length=1)

    @field_validator("trust_requirements")
    @classmethod
    def validate_unique_trust_requirements(
        cls, value: list[TrustRequirementOption]
    ) -> list[TrustRequirementOption]:
        if len(set(value)) != len(value):
            raise ValueError("trust_requirements must contain unique items")
        return value


class ResearchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    project: ProjectInput
    answers: QuizAnswers


# ---------------------------------------------------------------------------
# Response Schema Models (/shared/schemas/research_response.schema.json)
# ---------------------------------------------------------------------------


class PriceLineItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    label: str
    low: float | None = None
    high: float | None = None


class PriceEstimate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    low: float | None = None
    high: float | None = None
    currency: str
    line_items: list[PriceLineItem] = Field(default_factory=list)
    source_urls: list[str] = Field(default_factory=list)


class Certification(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str
    source_url: str | None = None


class ExpectedPrice(BaseModel):
    model_config = ConfigDict(extra="forbid")

    low: float | None = None
    high: float | None = None
    currency: str


class Subscores(BaseModel):
    model_config = ConfigDict(extra="forbid")

    price: float = Field(..., ge=0, le=100)
    reputation: float = Field(..., ge=0, le=100)
    fit: float = Field(..., ge=0, le=100)
    availability: float = Field(..., ge=0, le=100)


class CallBrief(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_price: float | None = None
    max_price: float | None = None
    leverage_points: list[str] = Field(default_factory=list)
    questions_to_ask: list[str] = Field(default_factory=list)


class Contractor(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    rank: int = Field(..., ge=1, le=5)
    name: str
    phone_e164: str
    phone_verified: bool
    phone_source_url: str | None = None
    website: str | None = None
    address: str | None = None
    trades: list[str] = Field(default_factory=list)
    rating: float | None = None
    review_count: int | None = None
    certifications: list[Certification] = Field(default_factory=list)
    insurance: str | None = None
    portfolio_urls: list[str] = Field(default_factory=list)
    expected_price: ExpectedPrice
    availability: str | None = None
    score: int | float = Field(..., ge=0, le=100)
    subscores: Subscores
    why_recommended: str
    red_flags: list[str] = Field(default_factory=list)
    source_urls: list[str] = Field(default_factory=list)
    call_brief: CallBrief


class ResearchResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    project_id: str
    is_demo: bool = False
    price_estimate: PriceEstimate
    contractors: list[Contractor] = Field(default_factory=list, max_length=5)
    warnings: list[str] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Job Status Schema Models (/shared/schemas/job_status.schema.json)
# ---------------------------------------------------------------------------

JobStatus = Literal["queued", "running", "completed", "failed"]
JobPhase = Literal["researching", "structuring", "verifying", "done"]


class JobStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: JobStatus
    phase: JobPhase
    result: ResearchResult | None = None
    error: str | None = None


class CreateJobResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    job_id: str


# ---------------------------------------------------------------------------
# Phase 2 LLM Extraction Models (StructuringExtraction)
# ---------------------------------------------------------------------------


class ExtractedContractor(BaseModel):
    """Contractor record extracted by the structuring model in Phase 2."""

    name: str
    phone_raw: str | None = None
    phone_source_url: str | None = None
    website: str | None = None
    address: str | None = None
    is_closed: bool = False
    business_status: str | None = None
    covers_scope: bool = True
    trades: list[str] = Field(default_factory=list)
    rating: float | None = None
    review_count: int | None = None
    certifications: list[Certification] = Field(default_factory=list)
    insurance: str | None = None
    portfolio_urls: list[str] = Field(default_factory=list)
    expected_price: ExpectedPrice
    availability: str | None = None
    subscores: Subscores
    why_recommended: str
    red_flags: list[str] = Field(default_factory=list)
    source_urls: list[str] = Field(default_factory=list)
    call_brief: CallBrief

    @model_validator(mode="before")
    @classmethod
    def normalize_input_aliases(cls, data: Any) -> Any:
        if isinstance(data, dict):
            # Support `phone` or `phone_e164` as alias for `phone_raw` if provided
            if data.get("phone_raw") is None:
                if "phone" in data and data["phone"] is not None:
                    data = dict(data)
                    data["phone_raw"] = data.pop("phone")
                elif "phone_e164" in data and data["phone_e164"] is not None:
                    data = dict(data)
                    data["phone_raw"] = data["phone_e164"]
        return data


class StructuringExtraction(BaseModel):
    """Top-level structured output returned by the Phase 2 LLM."""

    price_estimate: PriceEstimate
    contractors: list[ExtractedContractor] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Call & Scheduling Models (/shared/schemas/call_request.schema.json & call_status.schema.json)
# ---------------------------------------------------------------------------

CallStatus = Literal["queued", "running", "completed", "failed", "stopped"]
CallPhase = Literal["negotiating", "analyzing", "scheduling", "done"]
SpeakerRole = Literal["customer_agent", "renovator_agent"]
EndReason = Literal["agreement", "no_agreement", "stopped", "timeout", "error"]
BookingStatus = Literal["created", "link_only", "failed"]


class MeetingInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    customer_email: str = Field(..., min_length=1)
    address: str = Field(..., min_length=1)
    slots: list[str] = Field(default_factory=list)


class CallRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    job_id: str = Field(..., min_length=1)
    contractor_id: str = Field(..., min_length=1)
    meeting: MeetingInput


class CreateCallResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    call_id: str


class CallTurn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    index: int = Field(..., ge=0)
    speaker: SpeakerRole
    text: str
    audio_url: str | None = None


class CallOutcomeExtraction(BaseModel):
    """LLM structured output for call outcome extraction (no field named 'title')."""

    end_reason: EndReason
    opening_price: float | None = None
    final_price: float | None = None
    currency: str | None = None
    labour_included: bool | None = None
    materials_included: bool | None = None
    tax_included: bool | None = None
    scope_confirmed: bool | None = None
    agreed_slot: str | None = None
    notes: str | None = None


class CallOutcome(BaseModel):
    model_config = ConfigDict(extra="forbid")

    end_reason: EndReason
    opening_price: float | None = None
    final_price: float | None = None
    savings: float | None = None
    currency: str | None = None
    labour_included: bool | None = None
    materials_included: bool | None = None
    tax_included: bool | None = None
    scope_confirmed: bool | None = None
    agreed_slot: str | None = None
    notes: str | None = None


class MatchDecision(BaseModel):
    model_config = ConfigDict(extra="forbid")

    match: bool
    reasons: list[str] = Field(default_factory=list)


class BookingResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: BookingStatus
    starts_at: str | None = None
    location: str | None = None
    event_url: str | None = None
    warnings: list[str] = Field(default_factory=list)


class CallStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: CallStatus
    phase: CallPhase
    simulated: bool = True
    is_replay: bool = False
    turns: list[CallTurn] = Field(default_factory=list)
    outcome: CallOutcome | None = None
    match: MatchDecision | None = None
    booking: BookingResult | None = None
    warnings: list[str] = Field(default_factory=list)
    error: str | None = None


class AgentTurnOutput(BaseModel):
    """Structured output returned by TALK_MODEL for each speaker turn."""

    text: str
    end_call: bool = False
    end_reason: str | None = None


# ---------------------------------------------------------------------------
# Studio Render Models (/shared/schemas/render_request.schema.json & render_status.schema.json)
# ---------------------------------------------------------------------------

RenderMimeType = Literal["image/jpeg", "image/png", "image/webp"]
RenderStatus = Literal["queued", "running", "completed", "failed"]
RenderPhase = Literal["planning", "rendering", "narrating", "done"]


class RenderRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    image_base64: str = Field(..., min_length=1)
    mime_type: RenderMimeType
    instruction: str = Field(..., min_length=1, max_length=1000)
    city: str | None = None
    country: str | None = None


class RenderPlanExtraction(BaseModel):
    """Structured output from RENDER_PLAN_MODEL (no field named 'title')."""

    renovation_prompt: str = Field(..., min_length=1)
    voice_confirmation: str = Field(..., min_length=1)
    room: RoomInfo
    style: str = Field(..., min_length=1)
    work_items: list[WorkItem] = Field(..., min_length=1)


class RenderResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    before_url: str
    after_url: str
    renovation_prompt: str
    voice_confirmation: str
    audio_url: str | None = None
    model_used: str
    latency_ms: int = Field(..., ge=0)
    room: RoomInfo
    style: str = Field(..., min_length=1)
    work_items: list[WorkItem] = Field(..., min_length=1)


class RenderCreateResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    render_id: str
    status: RenderStatus


class RenderStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: RenderStatus
    phase: RenderPhase | None = None
    is_replay: bool = False
    result: RenderResult | None = None
    warnings: list[str] = Field(default_factory=list)
    error: str | None = None

