//
//  Transaction.swift
//  breadwallet
//
//  Created by Ehsan Rezaie on 2018-01-13.
//  Copyright © 2018-2019 Breadwinner AG. All rights reserved.
//

import Foundation
import BRCrypto

/// Transacton status
enum TransactionStatus {
    /// Zero confirmations
    case pending
    /// One or more confirmations
    case confirmed
    /// Sufficient confirmations to deem complete (coin-specific)
    case complete
    /// Invalid / error
    case invalid
}

/// Wrapper for BRCrypto TransferFeeBasis
struct FeeBasis {
    private let core: TransferFeeBasis
    
    let currency: Currency
    var amount: Amount {
        return Amount(cryptoAmount: core.fee, currency: currency)
    }
    var unit: CurrencyUnit {
        return core.unit
    }
    var pricePerCostFactor: Amount {
        return Amount(cryptoAmount: core.pricePerCostFactor, currency: currency)
    }
    var costFactor: Double {
        return core.costFactor
    }
    
    init(core: TransferFeeBasis, currency: Currency) {
        self.core = core
        self.currency = currency
    }
}

// MARK: -

/// Wrapper for BRCrypto Transfer
class Transaction {
    private let transfer: BRCrypto.Transfer
    let wallet: Wallet

    var metaDataContainer: MetaDataContainer?

    var currency: Currency { return wallet.currency }
    var confirmations: UInt64 {
        return transfer.confirmations ?? 0
    }
    var blockNumber: UInt64? {
        return transfer.confirmation?.blockNumber
    }
    //TODO:CRYPTO used as non-optional by tx metadata and rescan
    var blockHeight: UInt64 {
        return blockNumber ?? 0
    }

    var targetAddress: String { return transfer.target?.sanitizedDescription ?? "" }
    var sourceAddress: String { return transfer.source?.sanitizedDescription ?? "" }
    //TODO:CRYPTO legacy support
    var toAddress: String { return targetAddress }
    var fromAddress: String { return sourceAddress }

    var amount: Amount { return Amount(cryptoAmount: transfer.amount, currency: currency) }
    var fee: Amount { return Amount(cryptoAmount: transfer.fee, currency: wallet.feeCurrency) }

    var feeBasis: FeeBasis? {
        guard let core = (transfer.confirmedFeeBasis ?? transfer.estimatedFeeBasis) else { return nil }
        return FeeBasis(core: core,
                        currency: wallet.feeCurrency)
    }

    var created: Date? {
        if let confirmationTime = transfer.confirmation?.timestamp {
            return Date(timeIntervalSince1970: TimeInterval(confirmationTime))
        } else {
            return nil
        }
    }
    var timestamp: TimeInterval {
        if let timestamp = transfer.confirmation?.timestamp {
            return TimeInterval(timestamp)
        } else {
            return Date().timeIntervalSince1970
        }
    }

    var hash: String { return transfer.hash?.description ?? "" }

    var status: TransactionStatus {
        switch transfer.state {
        case .created, .signed, .submitted, .pending:
            return .pending
        case .included:
            switch Int(confirmations) {
            case 0:
                return .pending
            case 1..<currency.confirmationsUntilFinal:
                return .confirmed
            default:
                return .complete
            }
        case .failed, .deleted:
            return .invalid
        }
    }

    var direction: TransferDirection {
        return transfer.direction
    }

    // MARK: Init

    init(transfer: BRCrypto.Transfer, wallet: Wallet, kvStore: BRReplicatedKVStore?, rate: Rate?) {
        self.transfer = transfer
        self.wallet = wallet

        if let kvStore = kvStore, let metaDataKey = metaDataKey {
            metaDataContainer = MetaDataContainer(key: metaDataKey, kvStore: kvStore)
            // metadata is created for outgoing transactions when they are sent
            // incoming transactions only get metadata when they are recently confirmed to ensure
            // a relatively recent exchange rate is applied
            if let rate = rate,
                status != .complete && direction == .received {
                metaDataContainer!.createMetaData(tx: self, rate: rate)
            }
        }
    }
}

extension Transaction {

    var metaData: TxMetaData? { return metaDataContainer?.metaData }
    var comment: String? { return metaData?.comment }

    //TODO:CRYPTO remove this dependency
    var kvStore: BRReplicatedKVStore? { return nil }
    var hasKvStore: Bool { return kvStore != nil }

    var isPending: Bool { return status == .pending }
    var isValid: Bool { return status != .invalid }

    func createMetaData(rate: Rate, comment: String? = nil, feeRate: Double? = nil, tokenTransfer: String? = nil) {
        metaDataContainer?.createMetaData(tx: self, rate: rate, comment: comment, feeRate: feeRate, tokenTransfer: tokenTransfer)
    }

    func saveComment(comment: String, rate: Rate) {
        guard let metaDataContainer = metaDataContainer else { return }
        metaDataContainer.save(comment: comment, tx: self, rate: rate)
    }
}

extension Transaction: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(transfer.hash)
    }
}

// MARK: - Equatable support

func == (lhs: Transaction, rhs: Transaction) -> Bool {
    return lhs.hash == rhs.hash &&
        lhs.status == rhs.status &&
        lhs.comment == rhs.comment &&
        lhs.hasKvStore == rhs.hasKvStore
}

func == (lhs: [Transaction], rhs: [Transaction]) -> Bool {
    return lhs.elementsEqual(rhs, by: ==)
}

func != (lhs: [Transaction], rhs: [Transaction]) -> Bool {
    return !lhs.elementsEqual(rhs, by: ==)
}

// MARK: - Metadata Container

/// Encapsulates the transaction metadata in the KV store
class MetaDataContainer {
    var metaData: TxMetaData? {
        guard metaDataCache == nil else { return metaDataCache }
        guard let data = TxMetaData(txKey: key, store: kvStore) else { return nil }
        metaDataCache = data
        return metaDataCache
    }
    
    var kvStore: BRReplicatedKVStore
    
    private var key: String
    private var metaDataCache: TxMetaData?
    
    init(key: String, kvStore: BRReplicatedKVStore) {
        self.key = key
        self.kvStore = kvStore
    }
    
    /// Creates and stores new metadata in KV store if it does not exist
    func createMetaData(tx: Transaction, rate: Rate, comment: String? = nil, feeRate: Double? = nil, tokenTransfer: String? = nil) {
        guard metaData == nil else { return }
        
        let newData = TxMetaData(key: key,
                                 transaction: tx,
                                 exchangeRate: rate.rate,
                                 exchangeRateCurrency: rate.code,
                                 feeRate: feeRate ?? 0.0,
                                 deviceId: UserDefaults.deviceID,
                                 comment: comment,
                                 tokenTransfer: tokenTransfer)
        do {
            _ = try kvStore.set(newData)
        } catch let error {
            print("could not update metadata: \(error)")
        }
    }
    
    func save(comment: String, tx: Transaction, rate: Rate) {
        if let metaData = metaData {
            metaData.comment = comment
            do {
                _ = try kvStore.set(metaData)
            } catch let error {
                print("could not update metadata: \(error)")
            }
        } else {
            createMetaData(tx: tx, rate: rate, comment: comment)
        }
    }
}
