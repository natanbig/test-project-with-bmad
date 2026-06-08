package producer

import (
	"fmt"
	"math/rand"
	"sync/atomic"
	"time"

	"github.com/ejh/test-project-with-bmad/pkg/contract"
)

// Generator creates envelopes that satisfy configured payload bounds.
type Generator struct {
	producerID  string
	minBytes    uint64
	maxBytes    uint64
	compression string
	rand        *rand.Rand
	seq         uint64
}

func NewGenerator(cfg Config, seed int64) *Generator {
	if seed == 0 {
		seed = time.Now().UnixNano()
	}
	return &Generator{
		producerID:  cfg.ProducerID,
		minBytes:    cfg.PayloadMinBytes,
		maxBytes:    cfg.PayloadMaxBytes,
		compression: cfg.Compression,
		rand:        rand.New(rand.NewSource(seed)),
	}
}

// Next returns a compressed, contract-ready envelope.
func (g *Generator) Next(now time.Time) (contract.Envelope, error) {
	sz := g.minBytes
	if g.maxBytes > g.minBytes {
		sz += uint64(g.rand.Int63n(int64(g.maxBytes - g.minBytes + 1)))
	}

	raw := make([]byte, sz)
	if _, err := g.rand.Read(raw); err != nil {
		return contract.Envelope{}, fmt.Errorf("generate raw payload: %w", err)
	}

	compressed, compression, err := CompressPayload(g.compression, raw)
	if err != nil {
		return contract.Envelope{}, err
	}

	id := atomic.AddUint64(&g.seq, 1)

	envelope := contract.Envelope{
		MessageID:           fmt.Sprintf("%s-%d-%d", g.producerID, now.UnixNano(), id),
		ProducerID:          g.producerID,
		CreatedAtUnixMS:     now.UnixMilli(),
		Compression:         compression,
		OriginalSizeBytes:   uint64(len(raw)),
		CompressedSizeBytes: uint64(len(compressed)),
		Payload:             compressed,
	}
	return envelope, nil
}
