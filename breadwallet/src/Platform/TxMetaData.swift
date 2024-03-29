//
//  BRKVStoreObjects.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 8/13/16.
//  Copyright © 2016-2019 Breadwinner AG. All rights reserved.
//

import Foundation

// MARK: - Txn Metadata

// Txn metadata stores additional information about a given transaction
open class TxMetaData: BRKVStoreObject, BRCoding {
    var classVersion: Int = 3
    
    var blockHeight: Int = 0
    var exchangeRate: Double = 0
    var exchangeRateCurrency: String = ""
    var feeRate: Double = 0
    var size: Int = 0
    var created: Date = Date.zeroValue()
    var deviceId: String = ""
    var comment = ""
    var tokenTransfer = ""

    required public init?(coder decoder: BRCoder) {
        classVersion = decoder.decode("classVersion")
        if classVersion == Int.zeroValue() {
            //print("[BRTxMetadataObject] Unable to unarchive _TXMetadata: no version")
            return nil
        }
        blockHeight = decoder.decode("bh")
        exchangeRate = decoder.decode("er")
        exchangeRateCurrency = decoder.decode("erc")
        feeRate = decoder.decode("fr")
        size = decoder.decode("s")
        deviceId = decoder.decode("dId")
        created = decoder.decode("c")
        comment = decoder.decode("comment")
        tokenTransfer = decoder.decode("tokenTransfer")
        super.init(key: "", version: 0, lastModified: Date(), deleted: true, data: Data())
    }
    
    func encode(_ coder: BRCoder) {
        coder.encode(classVersion, key: "classVersion")
        coder.encode(blockHeight, key: "bh")
        coder.encode(exchangeRate, key: "er")
        coder.encode(exchangeRateCurrency, key: "erc")
        coder.encode(feeRate, key: "fr")
        coder.encode(size, key: "s")
        coder.encode(created, key: "c")
        coder.encode(deviceId, key: "dId")
        coder.encode(comment, key: "comment")
        coder.encode(tokenTransfer, key: "tokenTransfer")
    }

    /// Find metadata object based on the txKey
    public init?(txKey: String, store: BRReplicatedKVStore) {
        var ver: UInt64
        var date: Date
        var del: Bool
        var bytes: [UInt8]

        //print("[BRTxMetadataObject] find \(txKey)")
        do {
            (ver, date, del, bytes) = try store.get(txKey)
            let bytesDat = Data(bytes: &bytes, count: bytes.count)
            super.init(key: txKey, version: ver, lastModified: date, deleted: del, data: bytesDat)
            return
        } catch _ {
            //print("[BRTxMetadataObject] Unable to initialize BRTxMetadataObject: \(String(describing: e))")
        }

        return nil
    }
    
    /// Create new transaction metadata
    init(key: String,
         transaction: Transaction,
         exchangeRate: Double,
         exchangeRateCurrency: String,
         feeRate: Double? = nil,
         deviceId: String,
         comment: String? = nil,
         tokenTransfer: String? = nil) {
        print("[BRTxMetadataObject] new \(key)")
        super.init(key: key,
                   version: 0,
                   lastModified: Date(),
                   deleted: false,
                   data: Data())
        self.blockHeight = Int(transaction.blockHeight)
        self.created = Date()
        
        self.exchangeRate = exchangeRate
        self.exchangeRateCurrency = exchangeRateCurrency
        self.feeRate = feeRate ?? 0
        
        self.deviceId = deviceId
        self.comment = comment ?? ""

        //TODO:CRYPTO btc tx size
//        if let transaction = transaction as? BtcTransaction {
//            var rawTx = transaction.rawTransaction
//            self.size = BRTransactionSize(&rawTx)
//        }

        self.tokenTransfer = tokenTransfer ?? ""
    }
    
    override func getData() -> Data? {
        return BRKeyedArchiver.archivedDataWithRootObject(self)
    }
    
    override func dataWasSet(_ value: Data) {
        guard !value.isEmpty else { return }
        guard let s: TxMetaData = BRKeyedUnarchiver.unarchiveObjectWithData(value) else {
            print("[BRTxMetadataObject] unable to deserialise tx metadata")
            return
        }
        blockHeight = s.blockHeight
        exchangeRate = s.exchangeRate
        exchangeRateCurrency = s.exchangeRateCurrency
        feeRate = s.feeRate
        size = s.size
        created = s.created
        deviceId = s.deviceId
        comment = s.comment
        tokenTransfer = s.tokenTransfer
    }

}

extension Transaction {
    var sha256ofHash: String? {
        // The hash is a hex string, it was previously converted to bytes through UInt256
        // which resulted in a reverse-order byte array due to UInt256 being little-endian.
        // Reverse bytes to maintain backwards-compatibility with keys derived using the old scheme.
        return Data(hexString: hash, reversed: true)?.sha256.hexString
    }

    var metaDataKey: String? {
        guard let sha256hash = sha256ofHash else { return nil }
        //TODO:CRYPTO_V2 generic tokens
        return currency.isERC20Token ? "tkxf-\(sha256hash)" : "txn2-\(sha256hash)"
    }
}
