package producer

import (
	"context"
	"fmt"
	"time"
)

// RetryConfig defines bounded exponential backoff behavior.
type RetryConfig struct {
	MaxAttempts    int
	InitialBackoff time.Duration
	MaxBackoff     time.Duration
	Timeout        time.Duration
}

// RetryWithBackoff executes fn with bounded exponential backoff until success, timeout, or attempts exhausted.
func RetryWithBackoff(ctx context.Context, cfg RetryConfig, fn func(context.Context) error) error {
	if cfg.MaxAttempts < 1 {
		return fmt.Errorf("retry max attempts must be >= 1")
	}

	deadlineCtx, cancel := context.WithTimeout(ctx, cfg.Timeout)
	defer cancel()

	backoff := cfg.InitialBackoff
	if backoff <= 0 {
		backoff = 10 * time.Millisecond
	}
	if cfg.MaxBackoff <= 0 {
		cfg.MaxBackoff = backoff
	}

	var lastErr error
	for attempt := 1; attempt <= cfg.MaxAttempts; attempt++ {
		err := fn(deadlineCtx)
		if err == nil {
			return nil
		}
		lastErr = err
		if attempt == cfg.MaxAttempts {
			break
		}

		select {
		case <-deadlineCtx.Done():
			return fmt.Errorf("retry timeout after %d attempts: %w", attempt, lastErr)
		case <-time.After(backoff):
		}

		backoff *= 2
		if backoff > cfg.MaxBackoff {
			backoff = cfg.MaxBackoff
		}
	}

	return fmt.Errorf("retry exhausted after %d attempts: %w", cfg.MaxAttempts, lastErr)
}
