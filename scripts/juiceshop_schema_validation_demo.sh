#!/usr/bin/env bash
#
# Schema validation demo harness for OWASP Juice Shop behind Cloudflare.
#
# Sends pairs of compliant / non-compliant requests and reports whether each
# one was stopped at the Cloudflare edge or reached the origin.
#
# Usage:
#   BASE_URL=https://app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com \
#     ./schema_validation_demo.sh
#
# Note: compliant requests may still get 4xx from Juice Shop itself (wrong
# credentials, missing token, wrong captcha). That is expected: what matters
# is that they REACHED the origin instead of being blocked by Cloudflare.

set -euo pipefail

readonly BASE_URL="${BASE_URL:?Set BASE_URL to the public Cloudflare-proxied URL}"
readonly WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

failures=0

print_header() {
  printf '%-48s %-10s %-6s %-10s %s\n' "CASE" "EXPECTED" "HTTP" "RESULT" "CF-RAY"
  printf '%.0s-' {1..100}; printf '\n'
}

# Classifies a response as blocked by Cloudflare when it is a 403 HTML page
# served by the edge (block page contains the Cloudflare Ray ID footer).
classify_response() {
  local status="$1" body_file="$2"
  if [[ "${status}" == "403" ]] && grep -qi "cloudflare" "${body_file}"; then
    echo "edge-block"
  else
    echo "origin"
  fi
}

run_case() {
  local name="$1" expected="$2" method="$3" path="$4" body="${5:-}"
  local headers_file="${WORK_DIR}/headers" body_file="${WORK_DIR}/body"
  local -a curl_args=(-s -o "${body_file}" -D "${headers_file}" -w '%{http_code}' -X "${method}")

  if [[ -n "${body}" ]]; then
    curl_args+=(-H 'Content-Type: application/json' --data "${body}")
  fi

  local status
  status="$(curl "${curl_args[@]}" "${BASE_URL}${path}")"

  local actual ray verdict
  actual="$(classify_response "${status}" "${body_file}")"
  ray="$(grep -i '^cf-ray:' "${headers_file}" | awk '{print $2}' | tr -d '\r' || true)"

  if [[ "${actual}" == "${expected}" ]]; then
    verdict="PASS"
  else
    verdict="FAIL(${actual})"
    failures=$((failures + 1))
  fi

  printf '%-48s %-10s %-6s %-10s %s\n' "${name}" "${expected}" "${status}" "${verdict}" "${ray:--}"
}

main() {
  print_header

  # Login: type confusion and SQL injection bypass (Juice Shop "Login Admin").
  run_case "login: valid payload"            origin     POST "/rest/user/login" \
    '{"email":"demo@juice-sh.op","password":"wrong"}'
  run_case "login: email is a number"        edge-block POST "/rest/user/login" \
    '{"email":12345,"password":"x"}'
  run_case "login: missing password"         edge-block POST "/rest/user/login" \
    '{"email":"demo@juice-sh.op"}'
  run_case "login: SQLi in email"            edge-block POST "/rest/user/login" \
    "{\"email\":\"' OR 1=1--\",\"password\":\"x\"}"

  # Product lookup: path parameter must be a positive integer.
  run_case "product: numeric id"             origin     GET "/api/Products/1"
  run_case "product: non-numeric id"         edge-block GET "/api/Products/abc"

  # Search: free-text query restricted to a safe character set.
  run_case "search: plain term"              origin     GET "/rest/products/search?q=apple"
  run_case "search: UNION-based SQLi"        edge-block GET \
    "/rest/products/search?q=qwert%27%29%29%20UNION%20SELECT%20id%20FROM%20Users--"

  # Basket: negative quantity (Juice Shop "Payback Time").
  run_case "basket: quantity 1"              origin     POST "/api/BasketItems/" \
    '{"ProductId":1,"BasketId":"1","quantity":1}'
  run_case "basket: negative quantity"       edge-block POST "/api/BasketItems/" \
    '{"ProductId":1,"BasketId":"1","quantity":-100}'

  # Feedback: zero-star rating (Juice Shop "Zero Stars").
  run_case "feedback: rating 5"              origin     POST "/api/Feedbacks/" \
    '{"captchaId":0,"captcha":"0","comment":"Great shop","rating":5}'
  run_case "feedback: rating 0"              edge-block POST "/api/Feedbacks/" \
    '{"captchaId":0,"captcha":"0","comment":"Zero stars","rating":0}'

  printf '\n%d case(s) did not match the expected outcome.\n' "${failures}"
  [[ "${failures}" -eq 0 ]]
}

main "$@"
