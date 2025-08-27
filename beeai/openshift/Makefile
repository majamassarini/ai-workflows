deploy:
	./deploy.sh

run-jira-fetcher:
	oc apply -f configmap-x-jira-issue-fetcher.yml -n jotnar-prod
	oc delete job jira-issue-fetcher-manual -n jotnar-prod || true
	oc apply -f job-jira-issue-fetcher-manual.yml -n jotnar-prod

.PHONY: deploy run-jira-fetcher
