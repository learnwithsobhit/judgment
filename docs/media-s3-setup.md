# AWS S3 avatar uploads (Judgement)

Mirror of the Sabarimala media pattern: SigV4 presign → client PUT → confirm → store `public_url`.

## Env (Railway API)

| Variable | Example | Notes |
|----------|---------|-------|
| `FIREBASE_PROJECT_ID` | `judgment-railway-test` | Required for `POST /api/v1/auth/firebase` |
| `MEDIA_BACKEND` | `s3` | `s3`, `local`, or omit/`disabled` |
| `S3_BUCKET` | `judgement-avatars` | |
| `AWS_REGION` | `ap-south-1` | |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | IAM user | Put/DeleteObject + tagging on `avatars/*` |
| `MEDIA_PUBLIC_BASE_URL` | `https://dxxxx.cloudfront.net` | No trailing slash |
| `S3_PUBLIC_URL` | fallback if CloudFront unset | |
| `S3_ENDPOINT` | MinIO URL | Optional local |
| `UPLOAD_DIR` | `./uploads/avatars` | When `MEDIA_BACKEND=local` |
| `JUDGEMENT_FIREBASE_DEV_SECRET` | (tests only) | HS256 stand-in for Firebase ID tokens |

## Bucket checklist

1. CORS: `PUT`, `GET`, `HEAD` from Firebase Hosting origins + localhost
2. Public read via CloudFront+OAC **or** `s3:GetObject` on `avatars/*`
3. Lifecycle: expire objects tagged `state=unconfirmed` after 1 day
4. IAM: `s3:PutObject`, `s3:PutObjectTagging`, `s3:DeleteObject`, `s3:DeleteObjectTagging`

## Client PUT

Echo signed headers exactly (`Content-Type`, `x-amz-tagging`). Never send the Judgement bearer `Authorization` header to S3.
