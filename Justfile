# Run the Bootstrap playbook with the minimum set of tasks
bootstrap:
  ansible-playbook ansible/playbooks/bootstrap.yml --tags bootstrap
