package consumer

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"

	collectortrace "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	"google.golang.org/grpc"
)

// Receiver is an OTLP gRPC trace receiver for consumer envelopes.
type Receiver struct {
	collectortrace.UnimplementedTraceServiceServer

	cfg       Config
	validator *Validator
	metrics   *Metrics
	logger    *log.Logger
	server    *grpc.Server
}

func NewReceiver(cfg Config, validator *Validator, metrics *Metrics, logger *log.Logger) *Receiver {
	if logger == nil {
		logger = log.Default()
	}
	return &Receiver{
		cfg:       cfg,
		validator: validator,
		metrics:   metrics,
		logger:    logger,
		server:    grpc.NewServer(),
	}
}

func (r *Receiver) Start(ctx context.Context) error {
	ln, err := net.Listen("tcp", r.cfg.OTLPListenAddr)
	if err != nil {
		return fmt.Errorf("listen otlp grpc on %s: %w", r.cfg.OTLPListenAddr, err)
	}

	collectortrace.RegisterTraceServiceServer(r.server, r)

	go func() {
		<-ctx.Done()
		r.server.GracefulStop()
	}()

	if err := r.server.Serve(ln); err != nil && !errors.Is(err, grpc.ErrServerStopped) {
		return fmt.Errorf("serve otlp grpc: %w", err)
	}

	return nil
}

func (r *Receiver) Export(_ context.Context, req *collectortrace.ExportTraceServiceRequest) (*collectortrace.ExportTraceServiceResponse, error) {
	if req == nil {
		return &collectortrace.ExportTraceServiceResponse{}, nil
	}

	for _, rs := range req.ResourceSpans {
		for _, ss := range rs.ScopeSpans {
			for _, span := range ss.Spans {
				r.metrics.MessagesReceived.Inc()

				envelope, err := DecodeEnvelopeFromSpan(span)
				if err != nil {
					r.metrics.DecodeErrors.Inc()
					r.logger.Printf("decode envelope failed: %v", err)
					continue
				}

				if err := r.validator.Validate(envelope); err != nil {
					r.metrics.DecodeErrors.Inc()
					r.logger.Printf("invalid envelope: %v", err)
					continue
				}
			}
		}
	}

	return &collectortrace.ExportTraceServiceResponse{}, nil
}
