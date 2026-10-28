"""
SoundClock backend (FastAPI).

Kaam:
  * API keys server par rehti hain (app mein nahi).
  * Deezer / iTunes / Audius / YouTube se baat server karta hai, isliye web par
    CORS ka masla nahi aata.
  * Jawab cache hote hain (YouTube quota aur iTunes rate-limit bachta hai).

Chalane ka tareeqa:
    pip install -r requirements.txt
    uvicorn main:app --reload --port 8000
"""

from __future__ import annotations

import asyncio
import html
import logging
import os
import random
import re
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlparse

import httpx
from fastapi import FastAPI, HTTPException, Query, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

try:  # .env file hai to padh lo
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:  # pragma: no cover
    pass

log = logging.getLogger("soundclock")
logging.basicConfig(level=logging.INFO)
# httpx poora URL log karta hai (jis mein API key hoti hai), isliye uske logs band.
logging.getLogger("httpx").setLevel(logging.WARNING)

YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY", "").strip()
AUDIUS_API_KEY = os.getenv("AUDIUS_API_KEY", "").strip()
AUDIUS_APP_NAME = os.getenv("AUDIUS_APP_NAME", "soundclock").strip() or "soundclock"
ALLOWED_ORIGINS = [
    o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",") if o.strip()
]

DEEZER = "https://api.deezer.com"
ITUNES = "https://itunes.apple.com/search"
AUDIUS = "https://api.audius.co"
YOUTUBE = "https://www.googleapis.com/youtube/v3"

# Photo proxy: sirf ye hosts allowed hain (warna server ko SSRF ke liye istemal kiya ja sakta hai).
ALLOWED_IMAGE_HOSTS = ("googleusercontent.com", "ggpht.com")
MAX_IMAGE_BYTES = 5 * 1024 * 1024  # 5 MB

# --------------------------------------------------------------------------
# Artists (Top 50 inhi se banta hai, isliye ajeeb / English gaane nahi aate)
# --------------------------------------------------------------------------

PAKISTANI_ARTISTS = [
    "Atif Aslam",
    "Rahat Fateh Ali Khan",
    "Asim Azhar",
    "Ali Zafar",
    "Nusrat Fateh Ali Khan",
    "Abida Parveen",
    "Hasan Raheem",
    "Ali Sethi",
    "Shae Gill",
    "Talha Anjum",
    "Farhan Saeed",
    "Momina Mustehsan",
    "Bilal Saeed",
    "Junaid Jamshed",
    "Kaifi Khalil",
    "Young Stunners",
]

BOLLYWOOD_ARTISTS = [
    "Arijit Singh",
    "Jubin Nautiyal",
    "Shreya Ghoshal",
    "Sonu Nigam",
    "Neha Kakkar",
    "Badshah",
    "Armaan Malik",
    "Darshan Raval",
    "B Praak",
    "Vishal Mishra",
    "KK",
    "Sunidhi Chauhan",
]

BLOCKED_WORDS = [
    "instrumental",
    "karaoke",
    "backing track",
    "no vocals",
    "without vocals",
    "8d audio",
    "slowed",
    "reverb",
    "sped up",
    "nightcore",
]

VIDEO_SKIP_WORDS = ["reaction", "reacts", "karaoke", "instrumental", "tutorial", "status"]

# --------------------------------------------------------------------------
# Chhota TTL cache
# --------------------------------------------------------------------------


class TTLCache:
    def __init__(self, max_items: int = 500) -> None:
        self._data: dict[str, tuple[float, Any]] = {}
        self._max = max_items

    def get(self, key: str) -> Any | None:
        item = self._data.get(key)
        if item and item[0] > time.time():
            return item[1]
        self._data.pop(key, None)
        return None

    def set(self, key: str, value: Any, ttl: float) -> None:
        if len(self._data) >= self._max:
            now = time.time()
            for k in [k for k, (exp, _) in self._data.items() if exp <= now]:
                self._data.pop(k, None)
            if len(self._data) >= self._max:  # phir bhi bhara ho to sabse purana hatao
                oldest = min(self._data, key=lambda k: self._data[k][0])
                self._data.pop(oldest, None)
        self._data[key] = (time.time() + ttl, value)


cache = TTLCache()

_inflight: dict[str, "asyncio.Future[Any]"] = {}


async def cached(key: str, ttl: float, factory: Any) -> Any:
    """Cache + ek hi waqt ki same requests ko ek call mein jodta hai
    (taake audio aur video search ek hi YouTube call (100 units) share karein)."""
    hit = cache.get(key)
    if hit is not None:
        return hit
    task = _inflight.get(key)
    if task is None:
        task = asyncio.ensure_future(factory())
        _inflight[key] = task
        task.add_done_callback(lambda _t: _inflight.pop(key, None))
    result = await task
    cache.set(key, result, ttl)
    return result


# --------------------------------------------------------------------------
# HTTP client
# --------------------------------------------------------------------------

_http: httpx.AsyncClient | None = None


def client() -> httpx.AsyncClient:
    global _http
    if _http is None:
        _http = httpx.AsyncClient(
            timeout=20,
            follow_redirects=True,
            headers={"User-Agent": "SoundClock/1.0"},
        )
    return _http


async def _warm_up() -> None:
    """Server start hote hi naye gaane background mein load kar lo,
    taake app ki pehli request 30 second ke timeout mein na phanse."""
    try:
        songs = await fresh_songs()
        log.info("Warm-up done: %d fresh songs", len(songs))
    except Exception as e:  # noqa: BLE001
        log.warning("Warm-up failed: %s", e)


@asynccontextmanager
async def lifespan(_: FastAPI):
    warm = asyncio.create_task(_warm_up())
    yield
    warm.cancel()
    global _http
    if _http is not None:
        await _http.aclose()
        _http = None


app = FastAPI(title="SoundClock API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["*"],
)

# --------------------------------------------------------------------------
# Song helpers
# --------------------------------------------------------------------------


def make_song(
    song_id: str,
    title: str,
    artist: str,
    image: str,
    audio: str,
    duration: int,
) -> dict[str, Any]:
    return {
        "id": song_id,
        "title": title,
        "artist": artist,
        "imageUrl": image,
        "audioUrl": audio,
        "durationSec": duration,
    }


def artist_of(song: dict[str, Any]) -> str:
    return str(song["artist"]).split(" • ")[0].strip().lower()


def merge_unique(songs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for s in songs:
        if not str(s["audioUrl"]).strip() or not str(s["title"]).strip():
            continue
        key = f'{s["title"].strip().lower()}|{artist_of(s)}'
        if key not in seen:
            seen.add(key)
            out.append(s)
    return out


def round_robin(lists: list[list[dict[str, Any]]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    i = 0
    added = True
    while added:
        added = False
        for lst in lists:
            if i < len(lst):
                out.append(lst[i])
                added = True
        i += 1
    return out


# --------------------------------------------------------------------------
# Deezer
# --------------------------------------------------------------------------


async def deezer_search(q: str, limit: int = 25) -> list[dict[str, Any]]:
    q = q.strip()
    if not q:
        return []
    try:
        r = await client().get(f"{DEEZER}/search", params={"q": q, "limit": limit})
        r.raise_for_status()
        data = r.json().get("data") or []
    except Exception as e:  # noqa: BLE001
        log.warning("Deezer failed: %s", e)
        return []

    out: list[dict[str, Any]] = []
    for m in data:
        if not isinstance(m, dict):
            continue
        preview = str(m.get("preview") or "")
        title = str(m.get("title") or "")
        if not preview or not title.strip():
            continue
        artist = m.get("artist")
        album = m.get("album")
        artist_name = str(artist.get("name") or "Unknown") if isinstance(artist, dict) else "Unknown"
        cover = str(album.get("cover_medium") or "") if isinstance(album, dict) else ""
        out.append(
            make_song(f"deezer_{m.get('id')}", title, f"{artist_name} • Preview", cover, preview, 30)
        )
    return out


# --------------------------------------------------------------------------
# iTunes
# --------------------------------------------------------------------------


async def itunes_search(term: str, limit: int = 15, country: str = "US") -> list[dict[str, Any]]:
    term = term.strip()
    if not term:
        return []
    try:
        r = await client().get(
            ITUNES,
            params={
                "term": term,
                "media": "music",
                "entity": "song",
                "country": country.lower(),
                "limit": max(1, min(limit, 200)),
            },
        )
        r.raise_for_status()
        results = r.json().get("results") or []
    except Exception as e:  # noqa: BLE001
        log.warning("iTunes failed: %s", e)
        return []

    out: list[dict[str, Any]] = []
    for t in results:
        if not isinstance(t, dict):
            continue
        preview = str(t.get("previewUrl") or "")
        if not preview:
            continue
        art = re.sub(r"\d+x\d+bb", "300x300bb", str(t.get("artworkUrl100") or ""))
        out.append(
            make_song(
                f"itunes_{t.get('trackId', '')}",
                str(t.get("trackName") or "Unknown"),
                f"{t.get('artistName') or 'Unknown'} • Preview",
                art,
                preview,
                30,
            )
        )
    return out


# --------------------------------------------------------------------------
# Audius (poore gaane). Key server par rehti hai; app ko sirf /audius/stream/ID
# milta hai jo asal stream par redirect kar deta hai.
# --------------------------------------------------------------------------

AUDIUS_BAD_TITLES = [
    "instrumental",
    "karaoke",
    "backing track",
    "no vocals",
    "without vocals",
    "beat only",
    "type beat",
]


def _audius_params(extra: dict[str, Any]) -> dict[str, Any]:
    params: dict[str, Any] = {**extra, "app_name": AUDIUS_APP_NAME}
    if AUDIUS_API_KEY:
        params["api_key"] = AUDIUS_API_KEY
    return params


def _audius_song(track: dict[str, Any]) -> dict[str, Any] | None:
    tid = str(track.get("id") or "")
    title = str(track.get("title") or "")
    if not tid or not title.strip():
        return None
    if track.get("is_streamable") is False:
        return None
    duration = track.get("duration")
    if not isinstance(duration, (int, float)) or duration < 60:
        return None
    if any(w in title.lower() for w in AUDIUS_BAD_TITLES):
        return None
    user = track.get("user") if isinstance(track.get("user"), dict) else {}
    art = track.get("artwork") if isinstance(track.get("artwork"), dict) else {}
    image = str(art.get("480x480") or art.get("150x150") or art.get("1000x1000") or "")
    return make_song(
        f"audius_{tid}",
        title,
        str(user.get("name") or "Unknown"),
        image,
        f"/audius/stream/{tid}",  # relative; app backend ka URL aage laga leti hai
        int(duration),
    )


async def audius_tracks(path: str, params: dict[str, Any]) -> list[dict[str, Any]]:
    try:
        r = await client().get(f"{AUDIUS}{path}", params=_audius_params(params))
        r.raise_for_status()
        raw = r.json().get("data") or []
    except Exception as e:  # noqa: BLE001
        log.warning("Audius failed: %s", e)
        return []
    songs = [_audius_song(t) for t in raw if isinstance(t, dict)]
    return [s for s in songs if s]


# --------------------------------------------------------------------------
# Catalog (audio)
# --------------------------------------------------------------------------


def artist_matches(song: dict[str, Any], artist: str) -> bool:
    return artist.lower() in artist_of(song)


async def artist_songs(artist: str, allow_fallback: bool) -> list[dict[str, Any]]:
    songs = [s for s in await deezer_search(f'artist:"{artist}"', 12) if artist_matches(s, artist)]
    if not songs and allow_fallback:
        songs = [s for s in await itunes_search(artist, 12, "US") if artist_matches(s, artist)]
    return songs


async def side_songs(artists: list[str]) -> list[dict[str, Any]]:
    lists = await asyncio.gather(
        *[artist_songs(a, allow_fallback=i < 5) for i, a in enumerate(artists)]
    )
    return merge_unique(round_robin(list(lists)))


async def build_top50() -> list[dict[str, Any]]:
    bollywood, pakistani = await asyncio.gather(
        side_songs(BOLLYWOOD_ARTISTS), side_songs(PAKISTANI_ARTISTS)
    )

    out: list[dict[str, Any]] = []
    seen_titles: set[str] = set()

    def add(song: dict[str, Any]) -> None:
        if len(out) >= 50:
            return
        title = song["title"].strip().lower()
        if not title or not song["audioUrl"]:
            return
        if any(w in title for w in BLOCKED_WORDS):
            return
        if title in seen_titles:
            return
        seen_titles.add(title)
        out.append(song)

    for i in range(max(len(bollywood), len(pakistani))):
        if i < len(bollywood):
            add(bollywood[i])
        if i < len(pakistani):
            add(pakistani[i])
    return out


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", text.lower())).strip()


def _tokens(q: str) -> list[str]:
    return [t for t in _norm(q).split() if len(t) > 1]


def is_strong_match(song: dict[str, Any], q: str) -> bool:
    """Audius ke liye sakht shart: kam az kam 2 lafz aur sab gaane ke naam / artist mein.
    ("songs" jaise aam lafz par Audius ke ajeeb gaane nahi aayenge.)"""
    tokens = _tokens(q)
    if len(tokens) < 2:
        return _norm(song["title"]) == _norm(q)
    hay = _norm(f'{song["title"]} {song["artist"]}')
    return all(t in hay for t in tokens)


def title_rank(song: dict[str, Any], q: str) -> int:
    title, query = _norm(song["title"]), _norm(q)
    if title == query:
        return 0
    if title.startswith(query):
        return 1
    if query in title:
        return 2
    return 3


# --- YouTube video ke naam se audio dhoondna ------------------------------

_NOISE = re.compile(
    r"\b(official|video|audio|lyrics?|lyrical|full song|full video|full|hd|4k|8k|"
    r"music|song|songs|new|latest|hindi|punjabi|urdu|pakistani|bollywood|"
    r"ft|feat|featuring|out now|trending|viral|romantic|hit|hits|superhit|best)\b",
    re.IGNORECASE,
)


def song_name_guess(video_title: str) -> str:
    """'New Song 2026 | Teri Yaadon Mein Sanam | ...' se gaane ka asal naam nikalta hai."""
    title = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", video_title)
    for seg in re.split(r"\s*[|\u2013\u2014]\s*|\s-\s|:\s", title):
        cleaned = _NOISE.sub(" ", seg)
        cleaned = re.sub(r"\b\d+\b", " ", cleaned)
        cleaned = re.sub(r"[^\w\s]", " ", cleaned)
        cleaned = re.sub(r"\s+", " ", cleaned).strip()
        if len(cleaned) >= 4:
            return cleaned
    return ""


async def audio_for_video(video: dict[str, str], sem: asyncio.Semaphore) -> dict[str, Any] | None:
    guess = song_name_guess(video["title"])
    if not guess:
        return None
    async with sem:
        results = await deezer_search(guess, 5)
    video_norm = _norm(video["title"])
    guess_norm = _norm(guess)
    for song in results:
        # Deezer ke naam se "(From ...)" hata kar compare karo
        dz = _norm(re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", song["title"]))
        if len(dz) >= 4 and (guess_norm in dz or dz in video_norm):
            return song
    return None


async def audio_from_videos(videos: list[dict[str, str]]) -> list[dict[str, Any]]:
    sem = asyncio.Semaphore(5)
    found = await asyncio.gather(*[audio_for_video(v, sem) for v in videos])
    return merge_unique([s for s in found if s])


async def search_playable(q: str) -> list[dict[str, Any]]:
    """Audio list video list se milti-julti: YouTube ki videos ke gaanon ke 30 second
    preview, aur agar Audius par bilkul wahi gaana ho to poora gaana sabse upar."""

    async def videos_safe() -> list[dict[str, str]]:
        try:
            return await cached(f"videos-search:{q.lower()}", 15 * 60, lambda: youtube_search(q))
        except HTTPException:
            return []

    videos, audius = await asyncio.gather(
        videos_safe(), audius_tracks("/v1/tracks/search", {"query": q, "limit": 20})
    )

    full = sorted((s for s in audius if is_strong_match(s, q)), key=lambda s: title_rank(s, q))
    from_videos = await audio_from_videos(videos[:10])

    result = merge_unique([*full, *from_videos])
    if len(result) >= 5:
        return result

    # Video se kam gaane mile (ya YouTube na chale): seedha iTunes / Deezer search.
    in_, us, dz = await asyncio.gather(
        itunes_search(q, 15, "IN"),
        itunes_search(q, 15, "US"),
        deezer_search(q, 20),
    )
    return merge_unique([*result, *in_, *us, *dz])


# --------------------------------------------------------------------------
# Naye releases (artists ki sabse nayi albums / singles)
# --------------------------------------------------------------------------

_deezer_sem = asyncio.Semaphore(3)  # Deezer: 50 calls / 5 sec se neeche rehne ke liye
_itunes_sem = asyncio.Semaphore(1)  # iTunes ~20 calls/min allow karta hai


async def itunes_latest_tracks(name: str) -> list[dict[str, Any]]:
    """Deezer fail ho to iTunes se artist ke sabse naye gaane (releaseDate ke saath)."""
    key = f"itunes-latest:{name.lower()}"
    hit = cache.get(key)
    if hit is not None:
        return hit

    async with _itunes_sem:
        try:
            r = await client().get(
                ITUNES,
                params={
                    "term": name,
                    "media": "music",
                    "entity": "song",
                    "country": "in",
                    "limit": 50,
                },
            )
            await asyncio.sleep(1.5)  # rate-limit se bachne ke liye
            r.raise_for_status()
            results = r.json().get("results") or []
        except Exception as e:  # noqa: BLE001
            log.warning("iTunes latest failed (%s): %s", name, e)
            return []

    out: list[dict[str, Any]] = []
    for t in results:
        if not isinstance(t, dict) or not t.get("previewUrl"):
            continue
        if name.lower() not in str(t.get("artistName", "")).lower():
            continue
        released = str(t.get("releaseDate") or "")[:10]
        if not released:
            continue
        art = re.sub(r"\d+x\d+bb", "300x300bb", str(t.get("artworkUrl100") or ""))
        song = make_song(
            f"itunes_{t.get('trackId', '')}",
            str(t.get("trackName") or "Unknown"),
            f"{t.get('artistName') or name} • Preview",
            art,
            str(t["previewUrl"]),
            30,
        )
        song["released"] = released
        out.append(song)

    out.sort(key=lambda s: s["released"], reverse=True)
    out = out[:6]
    if out:  # khali jawab cache mat karo
        cache.set(key, out, 6 * 3600)
    return out


async def deezer_json(
    path: str, params: dict[str, Any] | None = None, retries: int = 3
) -> dict[str, Any]:
    for attempt in range(retries):
        try:
            async with _deezer_sem:
                r = await client().get(f"{DEEZER}{path}", params=params or {})
                await asyncio.sleep(0.35)  # ~8 calls/sec se zyada nahi
            r.raise_for_status()
            data = r.json()
        except Exception as e:  # noqa: BLE001
            log.warning("Deezer %s failed: %s", path, e)
            await asyncio.sleep(0.5 * (attempt + 1))
            continue

        # Deezer quota khatam hone par bhi HTTP 200 deta hai, body mein "error" hota hai.
        if isinstance(data, dict) and "error" in data:
            log.warning("Deezer %s error: %s", path, data["error"])
            await asyncio.sleep(1.5 * (attempt + 1))  # thora ruk kar dobara
            continue

        return data if isinstance(data, dict) else {}
    return {}


async def deezer_artist_id(name: str) -> int | None:
    key = f"artist-id:{name.lower()}"
    hit = cache.get(key)
    if hit:
        return hit
    data = await deezer_json("/search/artist", {"q": name, "limit": 3})
    for a in data.get("data") or []:
        if isinstance(a, dict) and name.lower() in str(a.get("name", "")).lower():
            found = int(a.get("id") or 0)
            if found:
                cache.set(key, found, 7 * 24 * 3600)
                return found
    return None  # fail ko cache nahi karte, agli baar dobara try hoga


async def artist_latest_tracks(name: str) -> list[dict[str, Any]]:
    """Artist ki 2 sabse nayi release ke gaane. Har gaane ke saath 'released' tarikh."""
    key = f"latest-tracks:{name.lower()}"
    hit = cache.get(key)
    if hit is not None:
        return hit

    aid = await deezer_artist_id(name)
    if not aid:
        return await itunes_latest_tracks(name)  # Deezer par artist nahi mila

    albums_raw = (await deezer_json(f"/artist/{aid}/albums", {"limit": 30})).get("data") or []
    albums = [a for a in albums_raw if isinstance(a, dict) and a.get("release_date")]
    albums.sort(key=lambda a: str(a["release_date"]), reverse=True)

    out: list[dict[str, Any]] = []
    for album in albums[:2]:
        tracks = (await deezer_json(f"/album/{album['id']}/tracks", {"limit": 6})).get("data") or []
        cover = str(album.get("cover_medium") or "")
        for t in tracks:
            if not isinstance(t, dict):
                continue
            preview = str(t.get("preview") or "")
            title = str(t.get("title") or "")
            if not preview or not title.strip():
                continue
            artist = t.get("artist") if isinstance(t.get("artist"), dict) else {}
            song = make_song(
                f"deezer_{t.get('id')}",
                title,
                f"{artist.get('name') or name} • Preview",
                cover,
                preview,
                30,
            )
            song["released"] = str(album["release_date"])
            out.append(song)

    if not out:  # Deezer se kuch na mila (rate-limit / koi release nahi) -> iTunes
        out = await itunes_latest_tracks(name)

    if out:  # khali jawab cache mat karo
        cache.set(key, out, 6 * 3600)
    return out


def _pick_fresh(lists: list[list[dict[str, Any]]], count: int) -> list[dict[str, Any]]:
    """Ek side (Bollywood ya Pakistani) ke artists ke sabse naye gaane chunta hai."""
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    tracks: list[dict[str, Any]] = []
    for lst in lists:
        lst = [t for t in lst if t["released"] <= today]  # aane wali (future) release nahi
        lst = sorted(lst, key=lambda s: s["released"], reverse=True)
        tracks.extend(lst[:5])  # ek artist ke 5 se zyada nahi

    tracks = [t for t in tracks if not any(w in t["title"].lower() for w in BLOCKED_WORDS)]

    # Pehle sirf bilkul taaza, kam hon to window badhao.
    chosen: list[dict[str, Any]] = []
    for days in (14, 30, 60, 120, 400, 1500):
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
        chosen = [t for t in tracks if t["released"] >= cutoff]
        if len(chosen) >= 10:
            break

    if not chosen:  # kuch na mile to jo hai wohi dikhao
        chosen = tracks

    chosen.sort(key=lambda s: s["released"], reverse=True)
    return merge_unique(chosen)[:count]


async def build_fresh(count: int = 60) -> list[dict[str, Any]]:
    """Bollywood aur Pakistani alag-alag chune jate hain, taake ek side doosri ko dabaye nahi."""
    bolly_lists, pak_lists = await asyncio.gather(
        asyncio.gather(*[artist_latest_tracks(a) for a in BOLLYWOOD_ARTISTS]),
        asyncio.gather(*[artist_latest_tracks(a) for a in PAKISTANI_ARTISTS]),
    )
    half = count // 2
    bolly = _pick_fresh(list(bolly_lists), half)
    pak = _pick_fresh(list(pak_lists), half)

    result = merge_unique([*bolly, *pak])
    result.sort(key=lambda s: s["released"], reverse=True)
    log.info("fresh: %d Bollywood + %d Pakistani", len(bolly), len(pak))
    return result


async def fresh_songs() -> list[dict[str, Any]]:
    """build_fresh ka cached version (khali jawab cache nahi hota)."""
    hit = cache.get("fresh")
    if hit is not None:
        return hit
    songs = await cached("fresh-build", 0, build_fresh)
    if songs:
        cache.set("fresh", songs, 30 * 60)
    return songs


# --------------------------------------------------------------------------
# YouTube (videos)
# --------------------------------------------------------------------------


async def yt_get(path: str, params: dict[str, Any]) -> dict[str, Any]:
    if not YOUTUBE_API_KEY:
        raise HTTPException(503, "YouTube API key server par set nahi hai.")
    try:
        r = await client().get(f"{YOUTUBE}{path}", params={**params, "key": YOUTUBE_API_KEY})
    except httpx.HTTPError as e:
        log.warning("YouTube network error: %s", e)
        raise HTTPException(502, "Server YouTube se connect nahi ho pa raha.") from e

    if r.status_code != 200:
        body = r.text
        log.warning("YouTube API error %s: %s", r.status_code, body[:300])
        if "quotaExceeded" in body or "dailyLimitExceeded" in body:
            raise HTTPException(429, "YouTube ka daily quota khatam ho gaya. Kal dobara chalega.")
        if "BLOCKED" in body or "referer" in body.lower():
            raise HTTPException(
                502,
                "YouTube key ki restriction block kar rahi hai. Server wali key par "
                "'HTTP referrer' restriction mat lagao.",
            )
        if "accessNotConfigured" in body or "SERVICE_DISABLED" in body:
            raise HTTPException(502, "Google Cloud mein YouTube Data API v3 enable nahi hai.")
        if "API_KEY_INVALID" in body or "keyInvalid" in body:
            raise HTTPException(502, "YouTube API key galat hai.")
        raise HTTPException(502, f"YouTube API error ({r.status_code}).")
    return r.json()


def yt_video(item: dict[str, Any]) -> dict[str, str] | None:
    snippet = item.get("snippet") if isinstance(item.get("snippet"), dict) else {}
    raw_id = item.get("id")
    if isinstance(raw_id, dict):
        video_id = str(raw_id.get("videoId") or "")
    elif isinstance(raw_id, str):
        video_id = raw_id
    else:
        video_id = ""

    thumbs = snippet.get("thumbnails") if isinstance(snippet.get("thumbnails"), dict) else {}
    thumb = thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {}
    title = html.unescape(str(snippet.get("title") or "Unknown title"))
    if not video_id or not title.strip():
        return None
    return {
        "videoId": video_id,
        "title": title,
        "channel": html.unescape(str(snippet.get("channelTitle") or "Unknown artist")),
        "thumbnailUrl": str(thumb.get("url") or "") if isinstance(thumb, dict) else "",
    }


async def yt_most_popular(region: str, limit: int = 25) -> list[dict[str, str]]:
    data = await yt_get(
        "/videos",
        {
            "part": "snippet,status",
            "chart": "mostPopular",
            "videoCategoryId": "10",
            "regionCode": region,
            "maxResults": limit,
        },
    )
    out = []
    for v in data.get("items") or []:
        if not isinstance(v, dict):
            continue
        status = v.get("status") if isinstance(v.get("status"), dict) else {}
        if status.get("embeddable") is False:
            continue
        video = yt_video(v)
        if video:
            out.append(video)
    return out


async def _pk_search(days: int, limit: int) -> list[dict[str, str]]:
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    data = await yt_get(
        "/search",
        {
            "part": "snippet",
            "type": "video",
            "q": "new pakistani song official music video",
            "maxResults": limit,
            "videoCategoryId": "10",
            "videoEmbeddable": "true",
            "videoSyndicated": "true",
            "regionCode": "PK",
            "relevanceLanguage": "ur",
            "order": "viewCount",
            "publishedAfter": since,
        },
    )
    seen: set[str] = set()
    videos: list[dict[str, str]] = []
    for item in data.get("items") or []:
        video = yt_video(item) if isinstance(item, dict) else None
        if not video:
            continue
        t = video["title"].lower()
        if any(w in t for w in VIDEO_SKIP_WORDS) or video["videoId"] in seen:
            continue
        seen.add(video["videoId"])
        videos.append(video)
    return videos


async def yt_pakistani_latest(limit: int = 25) -> list[dict[str, str]]:
    videos: list[dict[str, str]] = []
    try:
        for days in (45, 120):  # pehle sirf taaza (45 din); kam hon to 120 din
            videos = await _pk_search(days, limit)
            if len(videos) >= 10:
                break
    except HTTPException as e:
        log.warning("Pakistani search failed (%s), chart fallback", e.detail)

    if not videos:
        videos = await yt_most_popular("PK", limit)
    return videos


# --------------------------------------------------------------------------
# Routes
# --------------------------------------------------------------------------


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"ok": True, "youtube": bool(YOUTUBE_API_KEY), "audius": bool(AUDIUS_API_KEY)}


@app.get("/proxy/image")
async def proxy_image(url: str = Query(..., max_length=2000)) -> Response:
    """User ki photo (Google) server se guzaar kar deta hai, jab browser seedha load na kar sake.
    Sirf Google ke image hosts allowed hain."""
    p = urlparse(url)
    host = (p.hostname or "").lower()
    host_ok = any(host == h or host.endswith("." + h) for h in ALLOWED_IMAGE_HOSTS)
    if p.scheme != "https" or not host_ok:
        raise HTTPException(400, "Ye host allowed nahi hai.")

    key = f"img:{url}"
    hit = cache.get(key)
    if hit is None:
        try:
            # Redirect follow nahi karte, warna allowed host se bahar ja sakta hai.
            r = await client().get(url, follow_redirects=False)
        except httpx.HTTPError as e:
            log.warning("Image proxy failed: %s", e)
            raise HTTPException(502, "Photo laane mein masla.") from e

        ctype = r.headers.get("content-type", "")
        if r.status_code != 200 or not ctype.startswith("image/"):
            raise HTTPException(502, "Photo nahi mili.")
        if len(r.content) > MAX_IMAGE_BYTES:
            raise HTTPException(413, "Photo bohat bari hai.")

        hit = (r.content, ctype)
        cache.set(key, hit, 6 * 3600)

    content, ctype = hit
    return Response(
        content=content,
        media_type=ctype,
        headers={"Cache-Control": "public, max-age=86400"},
    )


@app.get("/home/fresh")
async def home_fresh() -> dict[str, Any]:
    """Naye gaane: saare artists ke sabse taaza, naya sabse upar."""
    songs = await fresh_songs()
    return {"songs": songs}


@app.get("/top50")
async def top50() -> dict[str, Any]:
    hit = cache.get("top50")
    if hit is not None:
        return {"songs": hit}
    songs = await build_top50()
    if songs:  # khali jawab cache mat karo
        cache.set("top50", songs, 20 * 60)
    return {"songs": songs}


@app.get("/search")
async def search(q: str = Query(..., min_length=1, max_length=100)) -> dict[str, Any]:
    key = f"search:{q.strip().lower()}"
    hit = cache.get(key)
    if hit is not None:
        return {"songs": hit}
    songs = await search_playable(q.strip())
    if songs:
        cache.set(key, songs, 10 * 60)
    return {"songs": songs}


@app.get("/deezer/preview/{track_id}")
async def deezer_preview(track_id: str) -> dict[str, str]:
    """Saved gaane ka taaza Deezer preview URL (purana expire ho jata hai)."""
    tid = track_id.replace("deezer_", "")
    if not tid.isdigit():
        raise HTTPException(400, "Galat track id.")
    try:
        r = await client().get(f"{DEEZER}/track/{tid}")
        r.raise_for_status()
        url = str(r.json().get("preview") or "")
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, "Deezer se preview nahi mila.") from e
    if not url:
        raise HTTPException(404, "Preview maujood nahi.")
    return {"url": url}


@app.get("/audius/trending")
async def audius_trending(
    genre: str | None = Query(None, max_length=40),
    time: str = Query("week", pattern="^(week|month|year|allTime)$"),
    limit: int = Query(30, ge=1, le=50),
) -> dict[str, Any]:
    key = f"audius-trending:{genre}:{time}:{limit}"
    hit = cache.get(key)
    if hit is not None:
        return {"songs": hit}
    params: dict[str, Any] = {"time": time, "limit": limit}
    if genre and genre.strip():
        params["genre"] = genre.strip()
    songs = await audius_tracks("/v1/tracks/trending", params)
    if songs:
        cache.set(key, songs, 15 * 60)
    return {"songs": songs}


@app.get("/audius/stream/{track_id}")
async def audius_stream(track_id: str) -> RedirectResponse:
    """Player yahan aata hai; hum asal Audius stream URL par redirect kar dete hain."""
    if not re.fullmatch(r"[A-Za-z0-9]{1,40}", track_id):
        raise HTTPException(400, "Galat track id.")
    try:
        r = await client().get(
            f"{AUDIUS}/v1/tracks/{track_id}/stream",
            params=_audius_params({"no_redirect": "true"}),
        )
        r.raise_for_status()
        url = str(r.json().get("data") or "")
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, "Audius stream nahi mila.") from e
    if not url.startswith("http"):
        raise HTTPException(404, "Stream URL nahi mila.")
    return RedirectResponse(url, status_code=302)


def _shuffled(result: dict[str, Any]) -> dict[str, Any]:
    """Cache wali list ka order har baar badal do (har run par alag videos pehle aayen)."""
    return {k: random.sample(v, len(v)) for k, v in result.items()}


@app.get("/videos/latest")
async def videos_latest() -> dict[str, Any]:
    hit = cache.get("videos-latest")
    if hit is not None:
        return _shuffled(hit)

    errors: list[HTTPException] = []

    async def guarded(coro: Any) -> list[dict[str, str]]:
        try:
            return await coro
        except HTTPException as e:
            errors.append(e)
            return []

    bollywood, pakistani = await asyncio.gather(
        guarded(yt_most_popular("IN")), guarded(yt_pakistani_latest())
    )
    if not bollywood and not pakistani and errors:
        raise errors[0]

    result = {"bollywood": bollywood, "pakistani": pakistani}
    if bollywood or pakistani:
        cache.set("videos-latest", result, 60 * 60)
    return _shuffled(result)


async def youtube_search(term: str) -> list[dict[str, str]]:
    data = await yt_get(
        "/search",
        {
            "part": "snippet",
            "type": "video",
            "q": term,
            "maxResults": 20,
            "videoCategoryId": "10",
            "videoEmbeddable": "true",
            "videoSyndicated": "true",
        },
    )
    seen: set[str] = set()
    videos: list[dict[str, str]] = []
    for item in data.get("items") or []:
        video = yt_video(item) if isinstance(item, dict) else None
        if video and video["videoId"] not in seen:
            seen.add(video["videoId"])
            videos.append(video)
    return videos


@app.get("/videos/search")
async def videos_search(q: str = Query(..., min_length=2, max_length=100)) -> dict[str, Any]:
    term = q.strip()
    videos = await cached(f"videos-search:{term.lower()}", 15 * 60, lambda: youtube_search(term))
    return {"videos": videos}