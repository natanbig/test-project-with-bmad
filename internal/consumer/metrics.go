package consumer

import "github.com/prometheus/client_golang/prometheus"

// Metrics bundles consumer counters required by the user story.
type Metrics struct {
	MessagesReceived prometheus.Counter
	DecodeErrors     prometheus.Counter
}

func NewMetrics(reg prometheus.Registerer) (*Metrics, error) {
	if reg == nil {
		reg = prometheus.DefaultRegisterer
	}

	m := &Metrics{
		MessagesReceived: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "okps_consumer_messages_received_total",
			Help: "Total number of consumer messages received.",
		}),
		DecodeErrors: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "okps_consumer_decode_errors_total",
			Help: "Total number of consumer decode or contract validation errors.",
		}),
	}

	if err := reg.Register(m.MessagesReceived); err != nil {
		return nil, err
	}
	if err := reg.Register(m.DecodeErrors); err != nil {
		return nil, err
	}

	return m, nil
}
