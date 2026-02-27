## 0.1.0

- Initial release.
- SC-AKE handshake protocol (Hashimoto et al. PQC 2022, Figure 4).
- SC-DAKE deniable variant with ring signatures.
- Key types: LongTermPublicKey, LongTermSecretKey, EphemeralPreKey, SessionId.
- Message types: PreKeyBundle, KeyExchangeMessage.
- Binary serialization with length-prefixed encoding.
- In-memory store implementations.
