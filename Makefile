# depends:
# - terraform
# - graphviz
# - jq
# - python3 + pip

# alias kitchen=make
.PHONY: create converge verify destroy clean clean-keys clean-all venv ping show lint

topology_id := 1
topology_file := topology.dot
venv := ansible/.venv
limit := *
ansible_flags = --limit="$(limit)"

topology_json = $(topology_file).json
terraform_state = topology-$(topology_id).tfstate
terraform_applied = .topology-$(topology_id).applied
terraform_destroyed = .topology-$(topology_id).destroyed
ansible_inventory = ansible/topology-$(topology_id).inventory

all: clean converge destroy

clean: clean-keys
	rm -f $(topology_json)
	rm -f $(terraform_applied)
	rm -f $(terraform_destroyed)
	rm -f $(terraform_state)

clean-keys:
	terraform output -json -state=$(terraform_state) ip_addrs | jq -r '.[]' | xargs -n1 ssh-keygen -R

clean-all: clean destroy
	rm -rf $(venv)

.DELETE_ON_ERROR:
$(topology_json): $(topology_file)
	dot -Tdot_json $(topology_file) > $@

create: $(terraform_applied)
.DELETE_ON_ERROR:
$(terraform_applied): $(topology_json)
	rm -f $(terraform_destroyed)
	env TF_IN_AUTOMATION=1 terraform apply -state=$(terraform_state) -input=false -auto-approve -var=topology_id=$(topology_id) -var=topology_file=$(topology_json)
	date +%s > $@

destroy: $(terraform_destroyed)
.DELETE_ON_ERROR:
$(terraform_destroyed): $(topology_json)
	rm -f $(terraform_applied)
	env TF_IN_AUTOMATION=1 terraform destroy -state=$(terraform_state) -input=false -auto-approve
	date +%s > $@

show:
	env TF_IN_AUTOMATION=1 terraform output -state=$(terraform_state) ssh_cmd

$(venv):
	python3 -m venv $(venv)

$(venv)/bin/ansible: | $(venv)
	source $(venv)/bin/activate && pip install -r ansible/requirements.txt

$(venv)/bin/ansible-lint: | $(venv)
	source $(venv)/bin/activate && pip install -r ansible/requirements.dev.txt

ansible_deps = $(venv) $(venv)/bin/ansible
ansible_lint_deps = $(venv) $(venv)/bin/ansible-lint

ping: $(terraform_applied) | $(ansible_deps) 
	$(venv)/bin/ansible -m ping -i $(ansible_inventory) -o all

converge: $(terraform_applied) | $(ansible_deps)
	$(venv)/bin/ansible-playbook ansible/site.yml -i $(ansible_inventory) $(ansible_flags)

verify: $(terraform_applied) | $(ansible_deps)
	$(venv)/bin/ansible-playbook ansible/site.yml -i $(ansible_inventory) --check --diff

lint: | $(ansible_lint_deps)
	source $(venv)/bin/activate && ansible-lint ansible/site.yml --offline --project-dir ansible
