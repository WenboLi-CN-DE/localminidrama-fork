#!/usr/bin/env bash
# LocalMiniDrama — WSL / Linux 一键启动开发环境
# 用法: bash run_dev.sh          # 前台运行（Ctrl+C 退出全部）
#       bash run_dev.sh -d       # 后台运行（日志写入 run_dev.log）
#       bash run_dev.sh stop     # 停止后台服务

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG="$ROOT/run_dev.log"
PID_DIR="$ROOT/.run_dev_pids"

# ── 颜色 ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── 停止后台服务 ───────────────────────────────────────
stop_services() {
  if [ -d "$PID_DIR" ]; then
    info "停止后台服务..."
    for pid_file in "$PID_DIR"/*.pid; do
      [ -f "$pid_file" ] || continue
      local name; name="$(basename "$pid_file" .pid)"
      local pid; pid="$(cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null && ok "已停止 $name (PID $pid)" || warn "$name (PID $pid) 已退出"
      else
        warn "$name (PID $pid) 已不在运行"
      fi
      rm -f "$pid_file"
    done
    rmdir "$PID_DIR" 2>/dev/null || true
    ok "全部服务已停止"
  else
    warn "没有找到运行中的后台服务"
  fi
  exit 0
}

[ "${1:-}" = "stop" ] && stop_services

DAEMON=false
[ "${1:-}" = "-d" ] && DAEMON=true

# ── 检查 Node.js ──────────────────────────────────────
if ! command -v node &>/dev/null; then
  err "未找到 node，请先安装 Node.js >= 18"
  exit 1
fi

NODE_VERSION="$(node -v | sed 's/^v//' | cut -d. -f1)"
if [ "$NODE_VERSION" -lt 18 ]; then
  err "Node.js 版本需要 >= 18，当前: $(node -v)"
  exit 1
fi

# ── 检查并安装依赖 ────────────────────────────────────
for dir in backend-node frontweb; do
  if [ ! -d "$ROOT/$dir/node_modules" ]; then
    info "安装 $dir 依赖..."
    (cd "$ROOT/$dir" && npm install)
  fi
done

# ── 杀掉占用端口的旧进程 ───────────────────────────────
kill_port() {
  local port=$1 name=$2
  local pids
  pids="$(lsof -ti :"$port" 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    for pid in $pids; do
      warn "端口 $port 被占用，终止进程 $pid..."
      kill "$pid" 2>/dev/null || true
    done
    sleep 1
  fi
}

kill_port 5679 "后端"
kill_port 3013 "前端"

# ── 启动函数 ───────────────────────────────────────────
start_backend() {
  info "启动后端 (backend-node) → http://localhost:5679"
  cd "$ROOT/backend-node"
  exec npm run dev
}

start_frontend() {
  info "启动前端 (frontweb) → http://localhost:3013"
  cd "$ROOT/frontweb"
  exec npm run dev
}

# ── 后台模式 ───────────────────────────────────────────
if $DAEMON; then
  mkdir -p "$PID_DIR"
  : > "$LOG"

  start_service() {
    local name=$1; shift
    "$@" >> "$LOG" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_DIR/$name.pid"
    ok "$name 已启动 (PID $pid)"
  }

  info "后台模式启动，日志: $LOG"
  info "停止服务: bash run_dev.sh stop"

  start_service backend start_backend
  start_service frontend start_frontend

  echo ""
  ok "开发服务器已启动！"
  echo -e "  后端:  ${YELLOW}http://localhost:5679${NC}"
  echo -e "  前端:  ${YELLOW}http://localhost:3013${NC}"
  echo -e "  日志:  ${CYAN}$LOG${NC}"
  echo -e "  停止:  ${CYAN}bash run_dev.sh stop${NC}"

  # WSL: 尝试用 Windows 浏览器打开
  if command -v cmd.exe &>/dev/null; then
    sleep 3
    cmd.exe /c start http://localhost:3013 2>/dev/null || true
  fi
  exit 0
fi

# ── 前台模式（并行启动，Ctrl+C 退出全部）────────────────
cleanup() {
  echo ""
  info "正在停止所有服务..."
  kill $(jobs -p) 2>/dev/null || true
  ok "已停止"
  exit 0
}
trap cleanup SIGINT SIGTERM

start_backend &
BACKEND_PID=$!

start_frontend &
FRONTEND_PID=$!

echo ""
ok "开发服务器已启动！"
echo -e "  后端:  ${YELLOW}http://localhost:5679${NC}  (PID $BACKEND_PID)"
echo -e "  前端:  ${YELLOW}http://localhost:3013${NC}  (PID $FRONTEND_PID)"
echo -e "  按 ${RED}Ctrl+C${NC} 停止全部服务"
echo ""

# WSL: 尝试用 Windows 浏览器打开
if command -v cmd.exe &>/dev/null; then
  sleep 3
  cmd.exe /c start http://localhost:3013 2>/dev/null || true
fi

# 等待任意子进程退出
wait -n 2>/dev/null || wait