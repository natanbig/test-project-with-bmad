.PHONY: \
	test \
	test-go \
	test-scripts \
	test-all \
	test-reconciliation \
	test-reconciliation-promql \
	test-load \
	test-resilience \
	run-producer \
	run-consumer \
	run-system \
	docker-build-producer \
	docker-build-consumer \
	docker-build-images \
	k8s-up \
	k8s-status \
	k8s-down

test: test-go

test-go:
	go test ./...

test-reconciliation:
	bash ./scripts/validate-reconciliation.sh

test-reconciliation-promql:
	bash ./scripts/validate-reconciliation-promql.sh

test-load:
	bash ./scripts/load/run-load-tests.sh

test-resilience:
	bash ./scripts/resilience/run-resilience-suite.sh

test-scripts: test-reconciliation test-reconciliation-promql test-load test-resilience

test-all: test-go test-scripts

run-producer:
	go run ./cmd/producer

run-consumer:
	go run ./cmd/consumer

# Start producer and consumer together; stop both with Ctrl+C.
run-system:
	@trap 'kill 0' INT TERM EXIT; \
	go run ./cmd/producer & \
	go run ./cmd/consumer & \
	wait

docker-build-producer:
	docker build -f Dockerfile.producer -t okps-producer:dev .

docker-build-consumer:
	docker build -f Dockerfile.consumer -t okps-consumer:dev .

docker-build-images: docker-build-producer docker-build-consumer

# Deploy full OKPS stack to local Kubernetes cluster.
k8s-up: docker-build-images
	kubectl apply -f deploy/k8s/namespace.yaml
	kubectl apply -f deploy/k8s/configmap.yaml
	kubectl apply -f deploy/k8s/prometheus-configmap.yaml
	kubectl apply -f deploy/k8s/grafana-configmap.yaml
	kubectl apply -f deploy/k8s/grafana-dashboard-configmap.yaml
	kubectl apply -f deploy/k8s/collector-service.yaml
	kubectl apply -f deploy/k8s/consumer-headless-service.yaml
	kubectl apply -f deploy/k8s/metrics-headless-services.yaml
	kubectl apply -f deploy/k8s/prometheus-service.yaml
	kubectl apply -f deploy/k8s/grafana-service.yaml
	kubectl apply -f deploy/k8s/producer-deployment.yaml
	kubectl apply -f deploy/k8s/collector-deployment.yaml
	kubectl apply -f deploy/k8s/consumer-deployment.yaml
	kubectl apply -f deploy/k8s/prometheus-deployment.yaml
	kubectl apply -f deploy/k8s/grafana-deployment.yaml
	kubectl apply -f deploy/k8s/hpa-producer.yaml
	kubectl apply -f deploy/k8s/hpa-collector.yaml
	kubectl apply -f deploy/k8s/hpa-consumer.yaml
	kubectl apply -f deploy/k8s/pdb-collector.yaml
	kubectl apply -f deploy/k8s/networkpolicy.yaml
	kubectl -n okps rollout restart deploy/okps-producer
	kubectl -n okps rollout restart deploy/okps-consumer
	kubectl -n okps rollout restart deploy/okps-prometheus
	kubectl -n okps rollout restart deploy/okps-grafana
	kubectl -n okps rollout status deploy/okps-producer
	kubectl -n okps rollout status deploy/okps-collector
	kubectl -n okps rollout status deploy/okps-consumer
	kubectl -n okps rollout status deploy/okps-prometheus
	kubectl -n okps rollout status deploy/okps-grafana

k8s-status:
	kubectl -n okps get pods
	kubectl -n okps get svc
	kubectl -n okps get hpa
	kubectl -n okps get pdb

k8s-down:
	kubectl delete -f deploy/k8s/grafana-deployment.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/prometheus-deployment.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/producer-deployment.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/collector-deployment.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/consumer-deployment.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/hpa-producer.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/hpa-collector.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/hpa-consumer.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/pdb-collector.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/networkpolicy.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/grafana-service.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/prometheus-service.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/metrics-headless-services.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/collector-service.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/consumer-headless-service.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/grafana-dashboard-configmap.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/grafana-configmap.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/prometheus-configmap.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/configmap.yaml --ignore-not-found=true
	kubectl delete -f deploy/k8s/namespace.yaml --ignore-not-found=true
