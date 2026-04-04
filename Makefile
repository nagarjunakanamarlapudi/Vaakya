# ============================================================
# Vaakya — Make Commands
# ============================================================
#
# App (Swift macOS/iOS):
#   make app-run              Run app → talks to local backend
#   make app-run-stg          Run app → talks to AWS staging
#   make app-run-prod         Run app → talks to AWS production
#   make app-dev              Run app from terminal with logs (local backend)
#   make app-dev-stg          Run app from terminal with logs (AWS staging)
#   make app-build            Build app only
#   make app-clean            Clean app build
#   make app-test             Run Swift E2E tests
#
# Backend (Python FastAPI):
#   make backend-run          Run backend locally (port 8002)
#   make backend-test         Run backend tests
#   make backend-lint         Lint + format
#   make backend-deploy-stg   Build + push + deploy to AWS staging
#   make backend-deploy-prod  Build + push + deploy to AWS production
#   make backend-undeploy-stg Destroy AWS staging
#   make backend-logs-stg     Stream staging Lambda logs
#   make backend-setup-stg    First-time AWS setup (Terraform + SSM + deploy)
#
# Infrastructure:
#   make infra-init           Initialize Terraform
#   make infra-plan-stg       Plan staging
#   make infra-deploy-stg     Apply staging Terraform
#   make ssm-list stage=stg   List SSM parameters
#   make ssm-seed-stg         Seed SSM parameters
#
# ============================================================

TF_DIR = infra
AWS_PROFILE ?= vaakya-dev
AWS_REGION ?= us-east-1

# ============================================================
# App (Swift)
# ============================================================

app-run:                         ## Run app (local backend)
	cd VaakyaApp && $(MAKE) run

app-run-stg:                     ## Run app (AWS staging backend)
	cd VaakyaApp && $(MAKE) run-stg

app-run-prod:                    ## Run app (AWS production backend)
	cd VaakyaApp && $(MAKE) run-prod

app-dev:                         ## Run app from terminal with logs (local backend)
	cd VaakyaApp && $(MAKE) dev

app-dev-stg:                     ## Run app from terminal with logs (AWS staging)
	cd VaakyaApp && $(MAKE) dev-stg

app-build:                       ## Build app only
	cd VaakyaApp && swift build

app-clean:                       ## Clean app build
	cd VaakyaApp && $(MAKE) clean

app-test:                        ## Run Swift E2E tests
	cd VaakyaApp && $(MAKE) e2e

app-fresh:                       ## Clean build + run (local backend)
	cd VaakyaApp && $(MAKE) fresh

# ============================================================
# Backend (Python FastAPI)
# ============================================================

backend-run:                     ## Run backend locally (port 8002, MinIO)
	VAAKYA_ENV=dev JWT_SECRET=dev-secret SHARE_SECRET=dev-share-secret uv run uvicorn vaakya.main:app --reload --port 8002

backend-test:                    ## Run backend tests
	VAAKYA_ENV=dev JWT_SECRET=test-secret SHARE_SECRET=test-share-secret uv run pytest tests/ -v --tb=short

backend-lint:                    ## Lint + format backend code
	uv run ruff check src/ tests/ --fix
	uv run ruff format src/ tests/

backend-audit:                   ## Check for dependency vulnerabilities
	uv audit

ECR_REPO = $$(cd $(TF_DIR) && terraform output -raw ecr_repository)

backend-deploy-%:                ## Deploy backend to AWS (make backend-deploy-stg)
	@echo "=== Deploying backend to $* ==="
	@echo "1/4 Building Docker image (linux/amd64)..."
	docker buildx build --platform linux/amd64 --provenance=false -f Dockerfile.lambda -t vaakya-api .
	@echo "2/4 Logging into ECR..."
	aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) | docker login --username AWS --password-stdin $(ECR_REPO)
	@echo "3/4 Pushing image to ECR..."
	docker tag vaakya-api:latest $(ECR_REPO):latest
	docker push $(ECR_REPO):latest
	@echo "4/4 Updating Lambda..."
	aws lambda update-function-code --function-name vaakya-api-$* --image-uri $(ECR_REPO):latest --region $(AWS_REGION) --profile $(AWS_PROFILE) > /dev/null
	@echo "=== Deployed. Testing health... ==="
	@sleep 10
	@curl -s $$(cd $(TF_DIR) && terraform output -raw api_url)/health

backend-undeploy-%:              ## Destroy AWS environment (make backend-undeploy-stg)
	@echo "WARNING: Destroying $* environment."
	$(call TF_INIT,$*)
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform destroy -var-file=config/$*.tfvars

backend-logs-%:                  ## Stream Lambda logs (make backend-logs-stg)
	aws logs tail /aws/lambda/vaakya-api-$* --follow --region $(AWS_REGION) --profile $(AWS_PROFILE)

backend-setup-%:                 ## First-time AWS setup: Terraform + SSM + deploy (make backend-setup-stg)
	@echo "=== First-time setup for $* ==="
	$(call TF_INIT,$*)
	$(MAKE) ssm-seed-$*
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform apply -var-file=config/$*.tfvars -auto-approve
	$(MAKE) backend-deploy-$*

# ============================================================
# Infrastructure (Terraform) — separate state per stage
# ============================================================
# Each stage (stg/prod) gets its own state file in S3:
#   s3://vaakya-terraform-state/infra/stg/terraform.tfstate
#   s3://vaakya-terraform-state/infra/prod/terraform.tfstate

# Init Terraform for a specific stage (must run before plan/deploy)
define TF_INIT
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform init \
		-reconfigure \
		-backend-config="key=infra/$(1)/terraform.tfstate" \
		-backend-config="profile=$(AWS_PROFILE)"
endef

infra-init-%:                    ## Init Terraform for stage (make infra-init-stg)
	$(call TF_INIT,$*)

infra-plan-%:                    ## Plan for environment (make infra-plan-stg)
	$(call TF_INIT,$*)
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform plan -var-file=config/$*.tfvars

infra-deploy-%:                  ## Apply Terraform (make infra-deploy-stg)
	$(call TF_INIT,$*)
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform apply -var-file=config/$*.tfvars -auto-approve

infra-destroy-%:                 ## Destroy Terraform resources (make infra-destroy-stg)
	@echo "WARNING: Destroying $* infrastructure."
	$(call TF_INIT,$*)
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform destroy -var-file=config/$*.tfvars

infra-output-%:                  ## Show Terraform outputs for stage (make infra-output-stg)
	$(call TF_INIT,$*)
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform output

infra-fmt:                       ## Format Terraform files
	cd $(TF_DIR) && terraform fmt -recursive

infra-validate:                  ## Validate Terraform configuration
	cd $(TF_DIR) && AWS_PROFILE=$(AWS_PROFILE) terraform init -backend=false && terraform validate

# ============================================================
# SSM Parameter Store
# ============================================================

ssm-check-%:                     ## Validate SSM params exist (make ssm-check-stg)
	@echo "Checking SSM parameters for stage=$*:"
	@grep 'path:' $(TF_DIR)/ssm-registry.yaml | sed 's/.*path: //' | while read -r path; do \
		resolved=$$(echo "$$path" | sed "s/{stage}/$*/g"); \
		if aws ssm get-parameter --name "$$resolved" --profile $(AWS_PROFILE) --region $(AWS_REGION) > /dev/null 2>&1; then \
			echo "  OK      $$resolved"; \
		else \
			echo "  MISSING $$resolved"; \
		fi; \
	done

ssm-list-%:                      ## List SSM params with values (make ssm-list-stg)
	@echo "SSM Parameters for stage=$*:"
	@grep 'path:' $(TF_DIR)/ssm-registry.yaml | sed 's/.*path: //' | while read -r path; do \
		resolved=$$(echo "$$path" | sed "s/{stage}/$*/g"); \
		val=$$(aws ssm get-parameter --name "$$resolved" --with-decryption --query "Parameter.Value" --output text --profile $(AWS_PROFILE) --region $(AWS_REGION) 2>/dev/null); \
		if [ -n "$$val" ] && [ "$$val" != "None" ]; then \
			echo "  $$resolved = $${val:0:4}****"; \
		else \
			echo "  $$resolved = (not set)"; \
		fi; \
	done

ssm-seed-%:                      ## Create missing SSM params (make ssm-seed-stg)
	@echo "Seeding SSM parameters for stage=$*..."
	@grep 'path:' $(TF_DIR)/ssm-registry.yaml | sed 's/.*path: //' | while read -r path; do \
		resolved=$$(echo "$$path" | sed "s/{stage}/$*/g"); \
		if ! aws ssm get-parameter --name "$$resolved" --profile $(AWS_PROFILE) --region $(AWS_REGION) > /dev/null 2>&1; then \
			if echo "$$resolved" | grep -q "jwt-secret\|share-secret"; then \
				val=$$(openssl rand -hex 32); \
				aws ssm put-parameter --name "$$resolved" --value "$$val" --type SecureString --profile $(AWS_PROFILE) --region $(AWS_REGION) > /dev/null; \
				echo "  Created $$resolved (generated)"; \
			else \
				aws ssm put-parameter --name "$$resolved" --value "PLACEHOLDER" --type SecureString --profile $(AWS_PROFILE) --region $(AWS_REGION) > /dev/null; \
				echo "  Created $$resolved (PLACEHOLDER — update manually)"; \
			fi; \
		else \
			echo "  Exists  $$resolved"; \
		fi; \
	done

# ============================================================
# Share Viewer
# ============================================================

share-deploy-%:                  ## Deploy share viewer SPA (make share-deploy-stg)
	aws s3 sync share-viewer/ s3://vaakya-share-$*/ --delete --profile $(AWS_PROFILE) --region $(AWS_REGION)
	aws cloudfront create-invalidation \
		--distribution-id $$(cd $(TF_DIR) && terraform output -raw cloudfront_distribution_id) \
		--paths "/*" \
		--profile $(AWS_PROFILE) --region $(AWS_REGION)

# ============================================================
# Help — Developer Cheat Sheet
# ============================================================

help:
	@echo ""
	@echo "  ╔═══════════════════════════════════════╗"
	@echo "  ║  Vaakya — Developer Cheat Sheet       ║"
	@echo "  ╚═══════════════════════════════════════╝"
	@echo ""
	@echo "  All commands: make <command>"
	@echo "  Quick start:  make app-fresh  (no server needed)"
	@echo ""
	@echo "  🖥️  APP (Swift macOS/iOS)"
	@echo "  ────────────────────────────────────────────────────────────────────"
	@echo "                           Dev (local)              Stg (AWS)                Prod (AWS)"
	@echo "  Run app                  app-run                  app-run-stg              app-run-prod"
	@echo "  Run with logs            app-dev                  app-dev-stg              -"
	@echo "  Clean build + run        app-fresh                -                        -"
	@echo "  Build only               app-build"
	@echo "  Clean                    app-clean"
	@echo "  E2E tests                app-test"
	@echo ""
	@echo "  🐍 BACKEND (Python FastAPI → Lambda)"
	@echo "  ────────────────────────────────────────────────────────────────────"
	@echo "                           Dev (local)              Stg (AWS)                Prod (AWS)"
	@echo "  Run server               backend-run              (Lambda)                 (Lambda)"
	@echo "  Deploy                   -                        backend-deploy-stg       backend-deploy-prod"
	@echo "  First-time setup         -                        backend-setup-stg        backend-setup-prod"
	@echo "  Undeploy                 -                        backend-undeploy-stg     backend-undeploy-prod"
	@echo "  Stream logs              (terminal)               backend-logs-stg         backend-logs-prod"
	@echo "  Tests                    backend-test"
	@echo "  Lint                     backend-lint"
	@echo ""
	@echo "  ☁️  INFRASTRUCTURE (Terraform)"
	@echo "  ────────────────────────────────────────────────────────────────────"
	@echo "                           Stg                      Prod"
	@echo "  Init                     infra-init-stg           infra-init-prod"
	@echo "  Plan                     infra-plan-stg           infra-plan-prod"
	@echo "  Apply                    infra-deploy-stg         infra-deploy-prod"
	@echo "  Destroy                  infra-destroy-stg        infra-destroy-prod"
	@echo "  Outputs                  infra-output-stg         infra-output-prod"
	@echo "  Format                   infra-fmt"
	@echo "  Validate                 infra-validate"
	@echo ""
	@echo "  🔐 SSM PARAMETER STORE"
	@echo "  ────────────────────────────────────────────────────────────────────"
	@echo "                           Dev                      Stg                      Prod"
	@echo "  Check params exist       ssm-check-dev            ssm-check-stg            ssm-check-prod"
	@echo "  List params (masked)     ssm-list-dev             ssm-list-stg             ssm-list-prod"
	@echo "  Seed missing params      ssm-seed-dev             ssm-seed-stg             ssm-seed-prod"
	@echo ""
	@echo "  🌐 SHARE VIEWER"
	@echo "  ────────────────────────────────────────────────────────────────────"
	@echo "  Deploy to S3             share-deploy-stg         share-deploy-prod"
	@echo ""
	@echo "  ────────────────────────────────────────────────────────────────────"
	@echo "  Config:   infra/config/{dev,stg,prod}.yaml"
	@echo "  Secrets:  infra/ssm-registry.yaml"
	@echo "  AWS:      profile=vaakya-dev  region=us-east-1"
	@echo ""

.DEFAULT_GOAL := help
