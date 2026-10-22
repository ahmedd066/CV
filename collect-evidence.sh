#!/bin/bash
if [ $# -ne 3 ]; then
  echo "Usage: $0 <bucket> <ec2-address> <lambda-address>"
  exit 1
fi

ROLL="23l-3092"
BUCKET="$1"
EC2="${2#http://}"; EC2="${EC2%/}"
LAM="${3#https://}"; LAM="${LAM%/}"
REGION=$(aws configure get region)
REGION=${REGION:-ap-southeast-2}
OUT=evidence.txt
: > "$OUT"

sec() {
  local name="$1"; shift
  echo "== $name ==" >> "$OUT"
  "$@" >> "$OUT" 2>&1 || echo "FAILED: $name" >> "$OUT"
  echo >> "$OUT"
}

policies() {
  for p in $(aws iam list-role-policies --role-name "$1" --query 'PolicyNames[]' --output text); do
    aws iam get-role-policy --role-name "$1" --policy-name "$p"
  done
}
lambda_pol() {
  aws iam list-attached-role-policies --role-name "cv-lambda-role-$ROLL"
  policies "cv-lambda-role-$ROLL"
}
endpoints() {
  for u in "http://$EC2/" "http://$EC2/style.css" "http://$EC2/cv.pdf" \
           "https://$LAM/" "https://$LAM/style.css" "https://$LAM/cv.pdf" \
           "https://$BUCKET.s3.$REGION.amazonaws.com/site/index.html"; do
    echo -n "$u -> "
    curl -s -o /dev/null -w "%{http_code} %{content_type}\n" "$u"
  done
}
instance() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=cv-ec2-$ROLL" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].{Type:InstanceType,IMDS:MetadataOptions.HttpTokens,Profile:IamInstanceProfile.Arn}'
}

sec caller          aws sts get-caller-identity
sec public-access   aws s3api get-public-access-block --bucket "$BUCKET"
sec versioning      aws s3api get-bucket-versioning --bucket "$BUCKET"
sec objects         aws s3 ls "s3://$BUCKET/site/"
sec ec2-policy      policies "cv-ec2-role-$ROLL"
sec lambda-policy   lambda_pol
sec security-group  aws ec2 describe-security-groups --group-names "cv-sg-$ROLL" --query 'SecurityGroups[].IpPermissions'
sec instance        instance
sec endpoints       endpoints
sec lambda-logs     aws logs tail "/aws/lambda/cv-func-$ROLL" --since 1d
sec log-retention   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/cv-func-$ROLL" --query 'logGroups[].retentionInDays'

echo DONE
