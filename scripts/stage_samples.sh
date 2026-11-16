#!/bin/bash
# Copies the reviewed sample knowledge files into a release, and nothing else.
#   stage_samples.sh <samples folder> <list of reviewed file names> <destination folder>
# Only files named in the list are copied (other files in the folder are left out and named).
# Stops when a listed file is missing, or when a sample looks private: a phone number (Chinese or
# foreign), an email, a WeChat ID, a labelled name or address, a street address, an ID number,
# an API key, or a folder path from someone's computer.
set -euo pipefail
export LC_ALL=en_US.UTF-8
SRC="$1"; LIST="$2"; DEST="$3"
mkdir -p "$DEST"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ ! -f "$SRC/$name" ]; then echo "Stopped: reviewed sample is missing: $name" >&2; exit 1; fi
  cp "$SRC/$name" "$DEST/$name"
done < "$LIST"
find "$SRC" -type f ! -name '.*' | while IFS= read -r file; do
  if ! grep -qxF "$(basename "$file")" "$LIST"; then echo "Not packaged (not in the reviewed list): $(basename "$file")"; fi
done

PRIVATE='1[3-9][0-9]([ -]?[0-9]){8}'                                   # Chinese mobile
PRIVATE+='|0[0-9]{2,3}-[0-9]{7,8}'                                     # landline
PRIVATE+='|\+[0-9]{1,3}[ -]?[0-9]([ -]?[0-9]){6,12}'                   # +country code
PRIVATE+='|(\([0-9]{3}\) ?|[0-9]{3}[-.])[0-9]{3}[-. ][0-9]{4}'         # (415) 555-0132
PRIVATE+='|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}'              # email
PRIVATE+='|(微信号?|[vV]信|[vVwW][xX]|weixin|wechat) *(号|id|ID)? *[:：是]? *[A-Za-z][A-Za-z0-9_-]{5,19}'   # WeChat ID
PRIVATE+='|(收货人|收件人|联系人|姓名) *[:：是 ]'                        # labelled name
PRIVATE+='|(详细地址|收货地址|收件地址|所在地区) *[:：]'                 # labelled address
PRIVATE+='|[一-龥]{2,}(路|街|大道|巷|弄)[0-9]+号|[0-9]+(栋|幢|号楼|单元)'   # street address
PRIVATE+='|[0-9]{17}[0-9Xx]'                                           # ID number
PRIVATE+='|sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'   # keys
PRIVATE+='|/Users/|/home/[a-z]|[A-Z]:\\Users'                          # machine paths
if grep -rnE "$PRIVATE" "$DEST"; then
  echo "Stopped: the sample knowledge above looks private." >&2
  exit 1
fi
