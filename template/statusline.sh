#!/bin/bash
set -f

# GNU coreutils (gdate/gstat) を優先。macOS の BSD date/stat は GNU 構文 (-d, -c) 非対応のため
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$HOME/.local/bin:/usr/bin:/bin:$PATH"

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
# ── Effort color temperature (max=熱/危険 … low=冷/安全) ──
eff_max='\033[38;2;255;70;70m'     # 赤
eff_xhigh='\033[38;2;255;140;40m'  # オレンジ
eff_high='\033[38;2;180;140;255m'  # 紫 (現状維持)
eff_medium='\033[38;2;0;180;90m'   # 緑
eff_low='\033[38;2;86;182;194m'    # シアン
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")
    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done
    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

# ── Single jq parse (stdin + cache merged) ──────────────
cache_file="/tmp/claude/statusline-usage-cache.json"
mkdir -p /tmp/claude 2>/dev/null
[ -f "$cache_file" ] || echo '{}' > "$cache_file"

now_epoch=$(date +%s)

# 1 jq call: parse stdin, merge cached usage, compute everything
parsed=$(echo "$input" | jq -r --slurpfile cache "$cache_file" --arg now "$now_epoch" '
    def nz(v): if (v == null or v == "") then "-" else (v|tostring) end;
    . as $in |
    ($cache[0] // {}) as $c |
    [
        nz($in.model.display_name // "Claude"),
        nz($in.context_window.context_window_size // 200000),
        nz((($in.context_window.current_usage.input_tokens // 0)
          + ($in.context_window.current_usage.cache_creation_input_tokens // 0)
          + ($in.context_window.current_usage.cache_read_input_tokens // 0))
          * 100 / ($in.context_window.context_window_size // 200000) | floor),
        nz($in.cwd),
        nz($in.session.start_time),
        nz($in.rate_limits.five_hour.used_percentage // $c.five_hour.utilization),
        nz($in.rate_limits.five_hour.resets_at // $c.five_hour.resets_at),
        nz($in.rate_limits.seven_day.used_percentage // $c.seven_day.utilization),
        nz($in.rate_limits.seven_day.resets_at // $c.seven_day.resets_at),
        nz($c.extra_usage.is_enabled // false),
        nz($c.extra_usage.utilization // 0),
        nz($c.extra_usage.used_credits // 0),
        nz($c.extra_usage.monthly_limit // 0),
        nz($in.effort.level)
    ] | join("\t")' 2>/dev/null)

IFS=$'\t' read -r model_name size pct_used cwd session_start \
    five_pct_raw five_iso seven_pct_raw seven_iso \
    extra_enabled extra_pct_raw extra_used_raw extra_limit_raw effort_in <<< "$parsed"

# Restore empty values from sentinel
for v in model_name size pct_used cwd session_start five_pct_raw five_iso \
         seven_pct_raw seven_iso extra_enabled extra_pct_raw extra_used_raw extra_limit_raw effort_in; do
    [ "${!v}" = "-" ] && eval "$v=''"
done

[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")
pct_color=$(color_for_pct "$pct_used")

# ── Effort level ────────────────────────────────────────
# セッション実値 (stdin の effort.level) を最優先。無ければ settings.json の
# 保存済みデフォルト (effortLevel) にフォールバック。
# settings.json だけ見ると /model でのセッション変更 (high→max 等) を取りこぼす。
effort="$effort_in"
if [ -z "$effort" ]; then
    effort=$(sed -n 's/.*"effortLevel"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME/.claude/settings.json" 2>/dev/null)
fi
[ -z "$effort" ] && effort="default"

# ── Git branch (skip dirty check for speed) ─────────────
git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null | head -1)" ]; then
        git_dirty="*"
    fi
fi

# ── Session duration ────────────────────────────────────
session_duration=""
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(date -d "$session_start" +%s 2>/dev/null)
    if [ -n "$start_epoch" ]; then
        elapsed=$(( now_epoch - start_epoch ))
        if [ "$elapsed" -ge 3600 ]; then
            session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
        elif [ "$elapsed" -ge 60 ]; then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi

# ── LINE 1 ──────────────────────────────────────────────
# effort の色 (アイコンは付けず、モデル名の直後に並べる)
case "$effort" in
    max)    eff_col="$eff_max" ;;
    xhigh)  eff_col="$eff_xhigh" ;;
    high)   eff_col="$eff_high" ;;
    medium) eff_col="$eff_medium" ;;
    low)    eff_col="$eff_low" ;;
    *)      eff_col="$dim" ;;
esac

line1="${blue}${model_name}${reset}${dim}:${reset}${eff_col}${effort}${reset}${sep}✍️ ${pct_color}${pct_used}%${reset}${sep}${cyan}${dirname}${reset}"
[ -n "$git_branch" ] && line1+=" ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
[ -n "$session_duration" ] && line1+="${sep}${dim}⏱ ${reset}${white}${session_duration}${reset}"

# ── Format epoch helper (no subshell) ───────────────────
fmt_time() { date -d "@$1" +"%H:%M" 2>/dev/null; }
fmt_datetime() { date -d "@$1" +"%b %-d, %H:%M" 2>/dev/null | tr 'A-Z' 'a-z'; }
fmt_date() { date -d "@$1" +"%b %-d" 2>/dev/null | tr 'A-Z' 'a-z'; }
# weekly 用: MM/DD(曜日) HH:MM 形式（曜日は日本語）
fmt_weekly() {
    local dow jp days
    dow=$(date -d "@$1" +%u 2>/dev/null)   # 1=月 .. 7=日
    days=(月 火 水 木 金 土 日)
    jp=${days[$((dow-1))]}
    date -d "@$1" +"%m/%d(${jp}) %H:%M" 2>/dev/null
}

# ── ISO → epoch (or pass-through if already epoch) ─────
iso_epoch() {
    [ -z "$1" ] || [ "$1" = "null" ] || [ "$1" = "" ] && return
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        printf "%s" "$1"
    else
        date -d "$1" +%s 2>/dev/null
    fi
}

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

if [ -n "$five_pct_raw" ] && [ "$five_pct_raw" != "null" ] && [ "$five_pct_raw" != "" ]; then
    five_pct=$(printf "%.0f" "$five_pct_raw" 2>/dev/null)
    five_reset_epoch=$(iso_epoch "$five_iso")
    five_reset=$([ -n "$five_reset_epoch" ] && fmt_time "$five_reset_epoch")
    five_bar=$(build_bar "$five_pct" "$bar_width")
    five_color=$(color_for_pct "$five_pct")
    rate_lines+="${white}current${reset} ${five_bar} ${five_color}$(printf '%3d' $five_pct)%${reset}"
    [ -n "$five_reset" ] && rate_lines+=" ${dim}⏰${reset} ${white}${five_reset}${reset}"
fi

if [ -n "$seven_pct_raw" ] && [ "$seven_pct_raw" != "null" ] && [ "$seven_pct_raw" != "" ]; then
    seven_pct=$(printf "%.0f" "$seven_pct_raw" 2>/dev/null)
    seven_reset_epoch=$(iso_epoch "$seven_iso")
    seven_reset=$([ -n "$seven_reset_epoch" ] && fmt_weekly "$seven_reset_epoch")
    seven_bar=$(build_bar "$seven_pct" "$bar_width")
    seven_color=$(color_for_pct "$seven_pct")
    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}weekly${reset}  ${seven_bar} ${seven_color}$(printf '%3d' $seven_pct)%${reset}"
    [ -n "$seven_reset" ] && rate_lines+=" ${dim}⏰${reset} ${white}${seven_reset}${reset}"
fi

if [ "$extra_enabled" = "true" ]; then
    extra_pct=$(printf "%.0f" "$extra_pct_raw" 2>/dev/null)
    extra_used=$(awk -v v="$extra_used_raw" 'BEGIN{printf "%.2f", v/100}')
    extra_limit=$(awk -v v="$extra_limit_raw" 'BEGIN{printf "%.2f", v/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")
    extra_color=$(color_for_pct "$extra_pct")
    extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr 'A-Z' 'a-z')
    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}extra${reset}   ${extra_bar} ${extra_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset} ${dim}⏰${reset} ${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

# ── Background: refresh API cache + dashboard POST ──────
(
    cache_age=999
    if [ -f "$cache_file" ]; then
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null)
        [ -n "$mtime" ] && cache_age=$(( now_epoch - mtime ))
    fi
    if [ "$cache_age" -gt 60 ]; then
        token="$CLAUDE_CODE_OAUTH_TOKEN"
        if [ -z "$token" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
            token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
        fi
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            response=$(curl -s --max-time 5 \
                -H "Accept: application/json" \
                -H "Authorization: Bearer $token" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "User-Agent: claude-code/2.1.34" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
                echo "$response" > "$cache_file"
            fi
        fi
    fi

    # ── Optional: local dashboard POST ──────────────────
    # ローカルで動かしているダッシュボードへメトリクスを送る任意機能。
    # サーバが無ければ無害に失敗する。不要ならこのブロックを削除してよい。
    if [ -n "$five_pct_raw" ] && [ "$five_pct_raw" != "null" ] && [ "$five_pct_raw" != "" ]; then
        five_pct_n=$(printf "%.0f" "$five_pct_raw" 2>/dev/null)
        five_reset_e=$(date -d "$five_iso" +%s 2>/dev/null)
        seven_pct_n=$(printf "%.0f" "$seven_pct_raw" 2>/dev/null)
        seven_reset_e=$(date -d "$seven_iso" +%s 2>/dev/null)
        payload=$(jq -n \
            --argjson five "$five_pct_n" --arg fr "${five_reset_e:-}" \
            --argjson seven "${seven_pct_n:-0}" --arg sr "${seven_reset_e:-}" \
            '{provider:"claude",source:"claude-statusline",url:"claude-code://statusline",title:"Claude Code statusLine",diagnostic:"Claude Code statusLine rate limits",metrics:[
                {id:"claude-five-hour",label:"5 hour limit",usedPercentage:$five,resetAt:$fr},
                {id:"claude-seven-day",label:"7 day limit",usedPercentage:$seven,resetAt:$sr}
            ]}' 2>/dev/null)
        [ -n "$payload" ] && curl -sS -m 1 -X POST \
            -H "content-type: application/json" \
            --data "$payload" \
            "http://127.0.0.1:43177/api/ingest" >/dev/null 2>&1 || true
    fi
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
