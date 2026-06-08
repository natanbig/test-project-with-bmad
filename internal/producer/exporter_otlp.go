package producer

import (
	"context"
	"fmt"

	"github.com/ejh/test-project-with-bmad/pkg/contract"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// EnvelopeExporter exports an envelope to the collector path.
type EnvelopeExporter interface {
	Export(context.Context, contract.Envelope) error
	Shutdown(context.Context) error
}

// OTLPExporter exports envelope telemetry over OTLP gRPC.
type OTLPExporter struct {
	provider *sdktrace.TracerProvider
	tracer   trace.Tracer
}

func NewOTLPExporter(ctx context.Context, cfg Config) (*OTLPExporter, error) {
	opts := []otlptracegrpc.Option{
		otlptracegrpc.WithEndpoint(cfg.OTLPEndpoint),
	}
	if cfg.OTLPInsecure {
		opts = append(opts, otlptracegrpc.WithInsecure())
	}

	exporter, err := otlptracegrpc.New(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("create otlp trace exporter: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("okps-producer"),
			attribute.String("producer.id", cfg.ProducerID),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("create resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	return &OTLPExporter{
		provider: tp,
		tracer:   tp.Tracer("okps/producer"),
	}, nil
}

func (e *OTLPExporter) Export(ctx context.Context, envelope contract.Envelope) error {
	_, span := e.tracer.Start(ctx, "okps.producer.send")
	span.SetAttributes(
		attribute.String("okps.message_id", envelope.MessageID),
		attribute.String("okps.producer_id", envelope.ProducerID),
		attribute.String("okps.compression", envelope.Compression),
		attribute.Int64("okps.original_size_bytes", int64(envelope.OriginalSizeBytes)),
		attribute.Int64("okps.compressed_size_bytes", int64(envelope.CompressedSizeBytes)),
	)
	span.End()
	return nil
}

func (e *OTLPExporter) Shutdown(ctx context.Context) error {
	return e.provider.Shutdown(ctx)
}
