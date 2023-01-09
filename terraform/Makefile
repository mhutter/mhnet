PLAN = terraform.tfplan

plan: $(PLAN)

$(PLAN):
	terraform plan -out $@

apply:
	terraform apply "$(PLAN)"

.PHONY: $(PLAN) apply
