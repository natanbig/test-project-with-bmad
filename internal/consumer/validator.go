package consumer

import (
	"github.com/ejh/test-project-with-bmad/pkg/contract"
)

// Validator enforces the payload envelope contract against configured bounds.
type Validator struct {
	payloadMinBytes uint64
	payloadMaxBytes uint64
}

func NewValidator(payloadMinBytes, payloadMaxBytes uint64) *Validator {
	return &Validator{
		payloadMinBytes: payloadMinBytes,
		payloadMaxBytes: payloadMaxBytes,
	}
}

func (v *Validator) Validate(e contract.Envelope) error {
	return contract.ValidateEnvelope(e, v.payloadMinBytes, v.payloadMaxBytes)
}
