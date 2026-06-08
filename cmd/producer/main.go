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
	"time"

	"github.com/ejh/test-project-with-bmad/internal/producer"
	"github.com/ejh/test-project-with-bmad/pkg/contract"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("producer failed: %v", err)
	}
}

func run() error {
	cfg, err := producer.LoadConfig()
	if err != nil {
		return err
	}

	metrics, err := producer.NewMetrics(nil)
	if err != nil {
		return fmt.Errorf("init metrics: %w", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})

	server := &http.Server{
		Addr:    cfg.MetricsListenAddr,
		Handler: mux,
	}
	go func() {
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("metrics server error: %v", err)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	exporter, err := producer.NewOTLPExporter(ctx, cfg)
	if err != nil {
		return err
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := exporter.Shutdown(shutdownCtx); err != nil {
			log.Printf("exporter shutdown error: %v", err)
		}
	}()

	gen := producer.NewGenerator(cfg, 0)
	ticker := time.NewTicker(cfg.SendInterval)
	defer ticker.Stop()

	log.Printf("producer started: endpoint=%s compression=%s payload=[%d,%d]",
		cfg.OTLPEndpoint,
		cfg.Compression,
		cfg.PayloadMinBytes,
		cfg.PayloadMaxBytes,
	)

	for {
		select {
		case <-ctx.Done():
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			return server.Shutdown(shutdownCtx)
		case now := <-ticker.C:
			envelope, err := gen.Next(now)
			if err != nil {
				metrics.SendErrors.Inc()
				log.Printf("generate envelope failed: %v", err)
				continue
			}

			if err := contract.ValidateEnvelope(envelope, cfg.PayloadMinBytes, cfg.PayloadMaxBytes); err != nil {
				metrics.SendErrors.Inc()
				log.Printf("invalid envelope: %v", err)
				continue
			}

			err = producer.RetryWithBackoff(ctx, cfg.Retry, func(opCtx context.Context) error {
				return exporter.Export(opCtx, envelope)
			})
			if err != nil {
				metrics.SendErrors.Inc()
				log.Printf("export failed: %v", err)
				continue
			}

			metrics.MessagesSent.Inc()
			metrics.PayloadBytes.Add(float64(envelope.OriginalSizeBytes))
		}
	}
}
