# Adapted from https://unix.stackexchange.com/a/348432 and https://lithic.tech/blog/2020-05/makefile-dot-env/
ifneq (,$(wildcard ./config/env))
include ./config/env
export
else
$(error env file doenst exist in the config folder, please see config/env.example for the format.)
endif

AWS_CMD = docker run --rm --env AWS_ACCESS_KEY_ID='$(AWS_ACCESS_KEY_ID)' --env AWS_SECRET_ACCESS_KEY='$(AWS_SECRET_ACCESS_KEY)' amazon/aws-cli
AWS_ECS_CMD = docker run --rm --env AWS_ACCESS_KEY_ID='$(AWS_ACCESS_KEY_ID)' --env AWS_SECRET_ACCESS_KEY='$(AWS_SECRET_ACCESS_KEY)' --env AWS_DEFAULT_REGION=$(AWS_REGION) amazon/aws-cli -- ecs
AWS_S3_PUBLIC_URL = https://$(AWS_S3_BUCKET_NAME).$(HOST_REGION).$(HOST_PROVIDER)/index.html
AWS_S3_ENDPOINT = https://$(HOST_REGION).$(HOST_PROVIDER)

ifeq ($(OS),Windows_NT)
# NOTE(jpr): see https://www.reddit.com/r/docker/comments/734arg/cant_figure_out_how_to_bash_into_docker_container/dnnz2uq/
BIN_SH_PATH = //bin/sh
else
BIN_SH_PATH = /bin/sh
endif

# Just using Make as a generic task-runner, not a compilation pipeline
.PHONY: %

################################################################################
# Main targets
################################################################################

docker-run: docker-build
	docker run --rm -v $(shell pwd)/.data:/opt/data \
		--env AWS_ACCESS_KEY_ID='$(AWS_ACCESS_KEY_ID)' \
		--env AWS_SECRET_ACCESS_KEY='$(AWS_SECRET_ACCESS_KEY)' \
		--env S3_BUCKET_NAME='$(AWS_S3_BUCKET_NAME)' \
		--env S3_ENDPOINT='$(AWS_S3_ENDPOINT)' \
		--env COD_SSO='$(COD_API_SSO)' \
		$(DOCKER_IMG_TAG)
	@echo
	@echo Deployment complete. You should be able to view your site at $(AWS_S3_PUBLIC_URL)

docker-query-player: ensure-args docker-build-quiet
	docker run --rm \
		--env COD_SSO='$(COD_API_SSO)' \
		$(DOCKER_IMG_TAG) $(BIN_SH_PATH) -c "cd fetcher && npm run-script query-player $(ARGS)"

check-bootstrap: silent-by-default check-docker-is-installed check-players-json-created ensure-api-credentials-set check-api-credentials-work ensure-aws-credentials-set check-aws-credentials-work ensure-s3-bucket-name-set check-s3-bucket-exists check-s3-bucket-is-website check-s3-bucket-has-public-policy
	@echo Everything looks good for bucket [$(AWS_S3_BUCKET_NAME)]
	@echo You should be able to view your site at $(AWS_S3_PUBLIC_URL) after you run \`make docker-run\`

ensure-bootstrap: silent-by-default check-docker-is-installed check-players-json-created ensure-api-credentials-set check-api-credentials-work ensure-aws-credentials-set check-aws-credentials-work ensure-s3-bucket-name-set ensure-s3-bucket-exists ensure-s3-bucket-is-website ensure-s3-bucket-has-public-policy
	@echo Everything should be setup for bucket [$(AWS_S3_BUCKET_NAME)]
	@echo You should be able to view your site at $(AWS_S3_PUBLIC_URL) after you run \`make docker-run\`

# https://developers.digitalocean.com/documentation/spaces/#aws-s3-compatibility
do-ensure-bootstrap: silent-by-default check-docker-is-installed check-players-json-created ensure-api-credentials-set check-api-credentials-work ensure-aws-credentials-set ensure-s3-bucket-name-set ensure-s3-bucket-exists ensure-s3-bucket-has-public-policy
	@echo Everything should be setup for bucket [$(AWS_S3_BUCKET_NAME)]
	@echo You should be able to view your site at $(AWS_S3_PUBLIC_URL) after you run \`make docker-run\`

################################################################################
# Other targets
################################################################################

docker-push: docker-build docker-login
	docker tag $(DOCKER_IMG_TAG):latest $(AWS_ECR_URL)/$(DOCKER_IMG_TAG):latest
	docker push $(AWS_ECR_URL)/$(DOCKER_IMG_TAG):latest

aws-delete-bucket:
	@echo "This will delete everything in [$(AWS_S3_BUCKET_NAME)]. Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]
	$(AWS_CMD) s3 rb s3://$(AWS_S3_BUCKET_NAME) --force

aws-list-ecs-tasks:
	@echo running:
	$(AWS_ECS_CMD) list-tasks --desired-status running --cluster default
	@echo stopped:
	$(AWS_ECS_CMD) list-tasks --desired-status stopped --cluster default

################################################################################
# Helpers
################################################################################

docker-build:
	docker build -t $(DOCKER_IMG_TAG) .

docker-build-quiet:
	docker build -q -t $(DOCKER_IMG_TAG) . >/dev/null

docker-login:
	$(AWS_CMD) ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ECR_URL)

ensure-api-credentials-set:
ifndef COD_API_SSO
	$(error COD_API_SSO is undefined)
endif
ifeq ($(COD_API_SSO),'')
	$(error COD_API_SSO is not set)
endif

ensure-aws-credentials-set:
ifndef AWS_ACCESS_KEY_ID
	$(error AWS_ACCESS_KEY_ID is undefined)
endif
ifeq ($(AWS_ACCESS_KEY_ID),'')
	$(error AWS_ACCESS_KEY_ID is not set)
endif
ifndef AWS_SECRET_ACCESS_KEY
	$(error AWS_SECRET_ACCESS_KEY is undefined)
endif
ifeq ($(AWS_SECRET_ACCESS_KEY),'')
	$(error AWS_SECRET_ACCESS_KEY is not set)
endif

check-docker-is-installed:
	which docker >/dev/null || (echo "docker is not installed, please install it first!" && exit 1)

check-players-json-created:
	[ -f config/players.json ] || (echo 'No players.json created in the config folder. Please see config/players.json.example for the format.' && exit 1)

check-aws-credentials-work:
	$(AWS_CMD) sts get-caller-identity >/dev/null || (echo "AWS credentials didnt work, please check them at https://console.aws.amazon.com/iam/home#/security_credentials" && exit 1)

check-api-credentials-work: docker-build-quiet
	docker run --rm \
		--env COD_SSO='$(COD_API_SSO)' \
		$(DOCKER_IMG_TAG) $(BIN_SH_PATH) -c "cd fetcher && npm run-script check-credentials" >/dev/null 2>&1 || (echo "COD credentials didnt work, please check them at https://my.callofduty.com/login" && exit 1)

check-s3-bucket-exists:
	$(AWS_CMD) s3api head-bucket --bucket $(AWS_S3_BUCKET_NAME) --endpoint-url $(AWS_S3_ENDPOINT) >/dev/null || (echo "Bucket [$(AWS_S3_BUCKET_NAME)] doesnt exist, create it first!" && exit 1)

check-s3-bucket-is-website:
	$(AWS_CMD) s3api get-bucket-website --bucket $(AWS_S3_BUCKET_NAME) --endpoint-url $(AWS_S3_ENDPOINT) >/dev/null || (echo "Bucket [$(AWS_S3_BUCKET_NAME)] is not an s3 website, enable the configuration!" && exit 1)

check-s3-bucket-has-public-policy:
	$(AWS_CMD) s3api get-bucket-policy --bucket $(AWS_S3_BUCKET_NAME) --endpoint-url $(AWS_S3_ENDPOINT) >/dev/null || (echo "Bucket [$(AWS_S3_BUCKET_NAME)] doesnt have a public policy, attach it first!" && exit 1)

ensure-s3-bucket-exists:
# NOTE(jpr): aws has different rules for us-east-1....
ifeq ($(AWS_REGION),us-east-1)
	$(MAKE) check-s3-bucket-exists >/dev/null 2>&1 || (echo "Bucket [$(AWS_S3_BUCKET_NAME)] doesnt exist, creating.." && $(AWS_CMD) s3api create-bucket --bucket $(AWS_S3_BUCKET_NAME) --region $(AWS_REGION) >/dev/null)
else
	$(MAKE) check-s3-bucket-exists >/dev/null 2>&1 || (echo "Bucket [$(AWS_S3_BUCKET_NAME)] doesnt exist, creating.." && $(AWS_CMD) s3api create-bucket --bucket $(AWS_S3_BUCKET_NAME) --region $(AWS_REGION) --create-bucket-configuration LocationConstraint=$(AWS_REGION) >/dev/null)
endif

ensure-s3-bucket-is-website:
	$(MAKE) check-s3-bucket-is-website >/dev/null 2>&1 || (echo "Bucket [$(AWS_S3_BUCKET_NAME)] is not an s3 website, enabling the configuration.." && $(AWS_CMD) s3 website s3://$(AWS_S3_BUCKET_NAME) --index-document index.html)

ensure-s3-bucket-has-public-policy:
	$(MAKE) check-s3-bucket-has-public-policy >/dev/null 2>&1 || (echo "Bucket [$(AWS_S3_BUCKET_NAME)] doesnt have a public policy, attaching.." && $(AWS_CMD) s3api --endpoint-url=$(AWS_S3_ENDPOINT) put-bucket-policy --bucket $(AWS_S3_BUCKET_NAME) --policy '{ "Statement": [ { "Effect": "Allow", "Principal": "*", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::$(AWS_S3_BUCKET_NAME)/*" } ] }')

ensure-s3-bucket-name-set:
ifndef AWS_S3_BUCKET_NAME
	$(error AWS_S3_BUCKET_NAME is undefined)
endif
ifeq ($(AWS_S3_BUCKET_NAME),'')
	$(error AWS_S3_BUCKET_NAME is not set)
endif

ensure-args:
ifndef ARGS
	$(error ARGS is undefined)
endif

silent-by-default:
ifndef VERBOSE
.SILENT:
endif
