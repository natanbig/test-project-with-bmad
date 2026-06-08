package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/ejh/test-project-with-bmad/internal/consumer"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("consumer failed: %v", err)
	}
}

func run() error {
	cfg, err := consumer.LoadConfig()
	if err != nil {
		return err
	}

	metrics, err := consumer.NewMetrics(nil)
	if err != nil {
		return fmt.Errorf("init metrics: %w", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})

	metricsServer := &http.Server{
		Addr:    cfg.MetricsListenAddr,
		Handler: mux,
	}
	go func() {
		if err := metricsServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("metrics server error: %v", err)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	validator := consumer.NewValidator(cfg.PayloadMinBytes, cfg.PayloadMaxBytes)
	receiver := consumer.NewReceiver(cfg, validator, metrics, log.Default())

	log.Printf("consumer started: otlp_listen=%s metrics_listen=%s payload=[%d,%d]",
		cfg.OTLPListenAddr,
		cfg.MetricsListenAddr,
		cfg.PayloadMinBytes,
		cfg.PayloadMaxBytes,
	)

	err = receiver.Start(ctx)
	shutdownErr := metricsServer.Shutdown(context.Background())
	if err != nil {
		return err
	}
	return shutdownErr
}
