"""Phase 3 (verifying): Pure Python phone normalisation, verification, filtering, deduplication, and deterministic ranking."""

from __future__ import annotations

import asyncio
import re
from urllib.parse import urlparse

import httpx
import phonenumbers
from phonenumbers import NumberParseException, PhoneNumberFormat

from app.config import settings
from app.models import (
    Contractor,
    ExtractedContractor,
    PriorityOption,
    ResearchRequest,
    ResearchResult,
    StructuringExtraction,
    Subscores,
)

COUNTRY_TO_REGION: dict[str, str] = {
    "france": "FR",
    "fr": "FR",
    "united kingdom": "GB",
    "uk": "GB",
    "gb": "GB",
    "great britain": "GB",
    "england": "GB",
    "scotland": "GB",
    "wales": "GB",
    "united states": "US",
    "united states of america": "US",
    "usa": "US",
    "us": "US",
    "u.s.": "US",
    "u.s.a.": "US",
    "germany": "DE",
    "deutschland": "DE",
    "de": "DE",
    "spain": "ES",
    "espana": "ES",
    "españa": "ES",
    "es": "ES",
    "italy": "IT",
    "italia": "IT",
    "it": "IT",
    "netherlands": "NL",
    "the netherlands": "NL",
    "holland": "NL",
    "nl": "NL",
    "switzerland": "CH",
    "suisse": "CH",
    "schweiz": "CH",
    "ch": "CH",
    "belgium": "BE",
    "belgique": "BE",
    "belgie": "BE",
    "belgië": "BE",
    "be": "BE",
    "canada": "CA",
    "ca": "CA",
    "australia": "AU",
    "au": "AU",
    "austria": "AT",
    "at": "AT",
    "portugal": "PT",
    "pt": "PT",
    "ireland": "IE",
    "ie": "IE",
    "luxembourg": "LU",
    "lu": "LU",
}

PRIORITY_WEIGHTS: dict[PriorityOption, tuple[float, float, float, float]] = {
    # (price, reputation, fit, availability)
    "lowest_price": (0.45, 0.25, 0.20, 0.10),
    "balanced": (0.30, 0.30, 0.30, 0.10),
    "quality": (0.10, 0.45, 0.35, 0.10),
    "design_match": (0.10, 0.25, 0.55, 0.10),
}

TRADE_SYNONYMS: dict[str, set[str]] = {
    "painting": {"painting", "paint", "painter", "peinture", "peintre"},
    "flooring": {"flooring", "floor", "floors", "parquet", "sol", "sols"},
    "plumbing": {"plumbing", "plumber", "plomberie", "plombier"},
    "electrical": {"electrical", "electrician", "electricity", "electricite", "électricité"},
    "joinery": {"joinery", "carpentry", "carpenter", "menuiserie", "menuisier"},
    "tiling": {"tiling", "tile", "tiles", "tiler", "carrelage", "carreleur"},
    "masonry": {"masonry", "mason", "maconnerie", "maçonnerie"},
}

ALL_TRADES_MARKERS: set[str] = {
    "all_trades",
    "all trades",
    "tous corps d'etat",
    "tous corps d'état",
    "general contractor",
    "general_contractor",
    "entreprise generale",
    "entreprise générale",
}

CLOSED_STATUS_MARKERS: set[str] = {
    "closed",
    "permanently_closed",
    "permanently closed",
    "dissolved",
    "liquidated",
    "inactive",
    "radié",
    "radie",
    "fermé",
    "ferme",
}


def country_to_region_code(country: str | None) -> str:
    """Resolve a country name or ISO-2 code to an uppercase ISO-2 region code."""
    if not country or not isinstance(country, str):
        return "FR"
    cleaned = country.strip().lower()
    if cleaned in COUNTRY_TO_REGION:
        return COUNTRY_TO_REGION[cleaned]
    if len(cleaned) == 2 and cleaned.isalpha():
        return cleaned.upper()
    return "FR"


def normalize_phone_e164(raw_phone: str | None, country: str = "France") -> str | None:
    """Normalise a phone number to E.164 format (+...) using phonenumbers and country."""
    if not raw_phone or not isinstance(raw_phone, str):
        return None
    cleaned = raw_phone.strip()
    if not cleaned or cleaned.lower() in {
        "not found",
        "n/a",
        "na",
        "none",
        "null",
        "unknown",
        "tbd",
    }:
        return None

    region = country_to_region_code(country)
    try:
        parsed = phonenumbers.parse(cleaned, region)
        if not phonenumbers.is_possible_number(parsed) or not phonenumbers.is_valid_number(parsed):
            return None
        return phonenumbers.format_number(parsed, PhoneNumberFormat.E164)
    except NumberParseException:
        return None


def _candidate_phone_digits(phone_e164: str) -> list[str]:
    """Build candidate digit sequences (full E.164, national significant, trunk-prefixed) for page matching."""
    candidates: list[str] = []
    full_digits = re.sub(r"\D", "", phone_e164)
    if len(full_digits) >= 7:
        candidates.append(full_digits)

    try:
        parsed = phonenumbers.parse(phone_e164, None)
        nsn = phonenumbers.national_significant_number(parsed)
        if nsn and len(nsn) >= 7:
            if f"0{nsn}" not in candidates:
                candidates.append(f"0{nsn}")
            if nsn not in candidates:
                candidates.append(nsn)
    except NumberParseException:
        pass

    return candidates


async def verify_phone_on_page(
    phone_e164: str,
    phone_source_url: str | None,
    timeout: float | None = None,
    http_client: httpx.AsyncClient | None = None,
) -> bool:
    """Fetch phone_source_url and check whether phone_e164 digits appear on the page."""
    if not phone_e164 or not phone_source_url or not isinstance(phone_source_url, str):
        return False

    url = phone_source_url.strip()
    if not url.startswith(("http://", "https://")):
        return False

    candidates = _candidate_phone_digits(phone_e164)
    if not candidates:
        return False

    req_timeout = timeout if timeout is not None else settings.phone_verify_timeout_seconds

    try:
        if http_client is not None:
            response = await http_client.get(url, timeout=req_timeout)
        else:
            async with httpx.AsyncClient(
                follow_redirects=True,
                timeout=req_timeout,
                headers={"User-Agent": "RenovationPipelineVerifier/1.0"},
            ) as client:
                response = await client.get(url)

        if response.status_code >= 400:
            return False

        page_digits = re.sub(r"\D", "", response.text or "")
        if not page_digits:
            return False

        return any(candidate in page_digits for candidate in candidates)
    except Exception:
        return False


def normalize_website_url(website: str | None) -> str | None:
    """Normalise a website URL for deduplication (strip scheme, www., and trailing slash)."""
    if not website or not isinstance(website, str):
        return None
    cleaned = website.strip().lower()
    if not cleaned or cleaned in {"not found", "n/a", "none", "null"}:
        return None

    if not cleaned.startswith(("http://", "https://")):
        cleaned = f"https://{cleaned}"

    try:
        parsed = urlparse(cleaned)
        host = (parsed.netloc or "").lower()
        if host.startswith("www."):
            host = host[4:]
        if not host:
            return None
        path = (parsed.path or "").rstrip("/")
        return f"{host}{path}"
    except Exception:
        return None


def compute_score(subscores: Subscores, priority: PriorityOption) -> int:
    """Deterministically compute 0-100 overall score from subscores and user priority."""
    w_price, w_rep, w_fit, w_avail = PRIORITY_WEIGHTS.get(
        priority, PRIORITY_WEIGHTS["balanced"]
    )
    weighted = (
        w_price * float(subscores.price)
        + w_rep * float(subscores.reputation)
        + w_fit * float(subscores.fit)
        + w_avail * float(subscores.availability)
    )
    clamped = max(0.0, min(100.0, weighted))
    return int(round(clamped))


def _contractor_is_closed(contractor: ExtractedContractor) -> bool:
    if contractor.is_closed:
        return True
    if contractor.business_status:
        status_lower = contractor.business_status.strip().lower()
        if status_lower in CLOSED_STATUS_MARKERS or any(
            marker in status_lower for marker in CLOSED_STATUS_MARKERS
        ):
            return True
    return False


def _contractor_covers_required_trades(
    contractor_trades: list[str],
    required_trades: list[str],
) -> bool:
    if not required_trades:
        return True
    normalized_contractor = [t.strip().lower() for t in contractor_trades if t and t.strip()]
    if not normalized_contractor:
        return False

    # Check if contractor explicitly states general / all-trades coverage
    if any(c_trade in ALL_TRADES_MARKERS for c_trade in normalized_contractor):
        return True

    for req in required_trades:
        req_clean = req.strip().lower()
        if not req_clean:
            continue
        synonyms = TRADE_SYNONYMS.get(req_clean, {req_clean})
        matched = False
        for c_trade in normalized_contractor:
            if c_trade == req_clean or c_trade in synonyms:
                matched = True
                break
            if any(syn in c_trade for syn in synonyms):
                matched = True
                break
        if not matched:
            return False
    return True


async def verify_and_rank_contractors(
    request: ResearchRequest,
    extraction: StructuringExtraction,
    http_client: httpx.AsyncClient | None = None,
) -> ResearchResult:
    """Execute Phase 3 verification, filtering, deduplication, and deterministic ranking."""
    country = request.project.client.country
    priority = request.answers.priority
    required_trades = [item.trade for item in request.project.work_items]

    # Step 1: Normalise phone numbers and filter invalid/closed/out-of-scope contractors
    qualifying: list[tuple[ExtractedContractor, str]] = []
    for candidate in extraction.contractors:
        if _contractor_is_closed(candidate):
            continue
        if not candidate.covers_scope:
            continue
        if not _contractor_covers_required_trades(candidate.trades, required_trades):
            continue

        phone_e164 = normalize_phone_e164(candidate.phone_raw, country)
        if phone_e164 is None:
            continue

        qualifying.append((candidate, phone_e164))

    # Step 2: Verify phone numbers on source URLs concurrently
    if qualifying:
        if http_client is not None:
            verifications = await asyncio.gather(
                *(
                    verify_phone_on_page(
                        phone_e164=phone_e164,
                        phone_source_url=cand.phone_source_url,
                        http_client=http_client,
                    )
                    for cand, phone_e164 in qualifying
                )
            )
        else:
            async with httpx.AsyncClient(
                follow_redirects=True,
                timeout=settings.phone_verify_timeout_seconds,
                headers={"User-Agent": "RenovationPipelineVerifier/1.0"},
            ) as shared_client:
                verifications = await asyncio.gather(
                    *(
                        verify_phone_on_page(
                            phone_e164=phone_e164,
                            phone_source_url=cand.phone_source_url,
                            http_client=shared_client,
                        )
                        for cand, phone_e164 in qualifying
                    )
                )
    else:
        verifications = []

    # Step 3: Build scored candidate objects
    scored_candidates: list[Contractor] = []
    for idx, ((cand, phone_e164), phone_verified) in enumerate(
        zip(qualifying, verifications), start=1
    ):
        score = compute_score(cand.subscores, priority)
        website_clean = (
            cand.website.strip()
            if cand.website
            and cand.website.strip().lower() not in {"not found", "n/a", "none", "null"}
            else None
        )
        phone_source_clean = (
            cand.phone_source_url.strip()
            if cand.phone_source_url
            and cand.phone_source_url.strip().lower()
            not in {"not found", "n/a", "none", "null"}
            else None
        )
        address_clean = (
            cand.address.strip()
            if cand.address
            and cand.address.strip().lower() not in {"not found", "n/a", "none", "null"}
            else None
        )
        insurance_clean = (
            cand.insurance.strip()
            if cand.insurance
            and cand.insurance.strip().lower() not in {"not found", "n/a", "none", "null"}
            else None
        )
        availability_clean = (
            cand.availability.strip()
            if cand.availability
            and cand.availability.strip().lower() not in {"not found", "n/a", "none", "null"}
            else None
        )

        scored_candidates.append(
            Contractor(
                id=f"c{idx}",
                rank=1,
                name=cand.name,
                phone_e164=phone_e164,
                phone_verified=bool(phone_verified),
                phone_source_url=phone_source_clean,
                website=website_clean,
                address=address_clean,
                trades=cand.trades,
                rating=cand.rating,
                review_count=cand.review_count,
                certifications=cand.certifications,
                insurance=insurance_clean,
                portfolio_urls=cand.portfolio_urls,
                expected_price=cand.expected_price,
                availability=availability_clean,
                score=score,
                subscores=cand.subscores,
                why_recommended=cand.why_recommended,
                red_flags=cand.red_flags,
                source_urls=cand.source_urls,
                call_brief=cand.call_brief,
            )
        )

    # Step 4: Sort with phone_verified == True first, then by score descending
    scored_candidates.sort(key=lambda c: (c.phone_verified, c.score), reverse=True)

    # Step 5: Deduplicate by phone_e164 and normalized website URL (keeping highest-ranked entry)
    deduped: list[Contractor] = []
    seen_phones: set[str] = set()
    seen_websites: set[str] = set()

    for contractor in scored_candidates:
        if contractor.phone_e164 in seen_phones:
            continue
        norm_site = normalize_website_url(contractor.website)
        if norm_site and norm_site in seen_websites:
            continue

        seen_phones.add(contractor.phone_e164)
        if norm_site:
            seen_websites.add(norm_site)
        deduped.append(contractor)

    # Step 6: Take at most top 5 and assign rank 1..len(top) and id c1..cN
    top_contractors = deduped[:5]
    for rank_idx, contractor in enumerate(top_contractors, start=1):
        contractor.rank = rank_idx
        contractor.id = f"c{rank_idx}"

    warnings = list(extraction.warnings)
    if len(top_contractors) < 5:
        warnings.append(
            f"Only {len(top_contractors)} qualifying contractors found after phone and scope verification (fewer than the target of 5)."
        )

    return ResearchResult(
        project_id=request.project.project_id,
        is_demo=False,
        price_estimate=extraction.price_estimate,
        contractors=top_contractors,
        warnings=warnings,
    )
