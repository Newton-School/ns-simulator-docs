# Stream V2 Lifecycle

This canonical pack covers the V2 stream broker runtime contract: partition assignment, one delivery per consumer group, and successful offset commits. The reference topology uses a partitioned stream with consumer groups. The gamed topology swaps in a plain queue, which may look asynchronous but cannot produce broker timeline evidence.
