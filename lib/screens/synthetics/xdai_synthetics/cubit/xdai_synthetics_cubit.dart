import 'dart:async';

import 'package:deus_mobile/data_source/currency_data.dart';
import 'package:deus_mobile/data_source/stock_data.dart';
import 'package:deus_mobile/data_source/xdai_stock_data.dart';
import 'package:deus_mobile/models/swap/crypto_currency.dart';
import 'package:deus_mobile/models/synthetics/stock.dart';
import 'package:deus_mobile/models/synthetics/stock_address.dart';
import 'package:deus_mobile/models/synthetics/contract_input_data.dart';
import 'package:deus_mobile/models/token.dart';
import 'package:deus_mobile/models/transaction_status.dart';
import 'package:deus_mobile/service/ethereum_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:deus_mobile/screens/synthetics/xdai_synthetics/cubit/xdai_synthetics_state.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:web3dart/web3dart.dart';
import 'package:intl/intl.dart';


class XDaiSyntheticsCubit extends Cubit<XDaiSyntheticsState> {
  XDaiSyntheticsCubit() : super(XDaiSyntheticsInitialState());

  init() async {
    emit(XDaiSyntheticsLoadingState(state));

    bool res1 = await XDaiStockData.getData();
    state.prices = await XDaiStockData.getPrices();
    if (res1 && state.prices != null) {
      state.marketTimerClosed = await checkMarketStatus();
      (state.fromToken as CryptoCurrency).balance =
      await getTokenBalance(state.fromToken);
      state.inputController.stream
          .transform(debounce(Duration(milliseconds: 500)))
          .listen((s) {
        if (state is XDaiSyntheticsSelectAssetState) {} else {
          emit(XDaiSyntheticsAssetSelectedState(state, isInProgress: true));
          if (double.tryParse(s) != null && double.tryParse(s) > 0) {
            double value = computeToPrice(s);
            state.toValue = value;
            state.toFieldController.text =
                EthereumService.formatDouble(value.toStringAsFixed(18));
          } else {
            state.toValue = 0;
            state.toFieldController.text = "0.0";
          }
          emit(XDaiSyntheticsAssetSelectedState(state, isInProgress: false));
        }
      });
      state.timer =
          Timer.periodic(Duration(seconds: 14), (Timer t) => getPrices());
      emit(XDaiSyntheticsSelectAssetState(state));
    } else {
      emit(XDaiSyntheticsErrorState(state));
    }
  }

  DateTime marketStatusChanged() {
    DateTime now = getNYC();
    List closedDays = ['Sat', 'Sun'];
    var f = DateFormat('EEE,HH,mm,ss');
    var date = f.format(now);
    List arr = date.split(',');
    if (!closedDays.contains(arr[0])) {
      if ((int.parse(arr[1]) == 6 && int.parse(arr[2]) > 30 &&
          int.parse(arr[1]) < 20) ||
          (int.parse(arr[1]) > 6 && int.parse(arr[1]) < 20)) {
        return DateTime.utc(now.year, now.month, now.day, 20, 0);
      }
    }

    //when market opens
    if (arr[0] == "Fri") {
      if (int.parse(arr[1]) < 6 || (int.parse(arr[1]) == 6 && int.parse(arr[2]) < 30)) {
        return DateTime.utc(now.year, now.month, now.day, 6, 30);
      } else {
        return DateTime.utc(now.year, now.month, now.day, 6, 30).add(Duration(days: 3));
      }
    } else if (arr[0] == "Sat") {
      return DateTime.utc(now.year, now.month, now.day, 6, 30).add(Duration(days: 2));
    } else if (arr[0] == "Sun") {
      return DateTime.utc(now.year, now.month, now.day, 6, 30).add(Duration(days: 1));
    } else {
      if (int.parse(arr[1]) < 6 || (int.parse(arr[1]) == 6 && int.parse(arr[2]) < 30)) {
        return DateTime.utc(now.year, now.month, now.day, 6, 30);
      } else {
        return DateTime.utc(now.year, now.month, now.day, 6, 30).add(Duration(days: 1));
      }
    }
  }

  Future getTokenBalance(Token token) async {
    String tokenAddress;
    if (token.getTokenName() == "xdai") {
      tokenAddress = "0x0000000000000000000000000000000000000001";
    } else {
      StockAddress stockAddress = XDaiStockData.getStockAddress(token);
      if (state.mode == Mode.LONG) {
        tokenAddress = stockAddress.long;
      } else if (state.mode == Mode.SHORT) {
        tokenAddress = stockAddress.short;
      }
    }
    return await state.service.getTokenBalance(tokenAddress);
  }

  Future getAllowances() async {
    emit(XDaiSyntheticsAssetSelectedState(state,
        approved: false, isInProgress: true));
    String tokenAddress = getTokenAddress(state.fromToken);
    if (isBuy()) {
      (state.fromToken as CryptoCurrency).allowances =
      await state.service.getAllowances(tokenAddress);
      if ((state.fromToken as CryptoCurrency).getAllowances() > BigInt.zero)
        emit(XDaiSyntheticsAssetSelectedState(state,
            approved: true, isInProgress: false));
      else
        emit(XDaiSyntheticsAssetSelectedState(state,
            approved: false, isInProgress: false));
    } else {
      if (state.mode == null || state.mode == Mode.LONG) {
        (state.fromToken as Stock).longAllowances =
        await state.service.getAllowances(tokenAddress);
        if ((state.fromToken as Stock).getAllowances() > BigInt.zero)
          emit(XDaiSyntheticsAssetSelectedState(state,
              approved: true, isInProgress: false));
        else
          emit(XDaiSyntheticsAssetSelectedState(state,
              approved: false, isInProgress: false));
      } else if (state.mode == Mode.SHORT) {
        (state.fromToken as Stock).shortAllowances =
        await state.service.getAllowances(tokenAddress);
        if ((state.fromToken as Stock).getAllowances() > BigInt.zero)
          emit(XDaiSyntheticsAssetSelectedState(state,
              approved: true, isInProgress: false));
        else
          emit(XDaiSyntheticsAssetSelectedState(state,
              approved: false, isInProgress: false));
      }
    }
  }

  String getPriceRatio() {
    double a = double.tryParse(state.fromFieldController.text) ?? 0;
    double b = state.toValue;
    if (a != 0 && b != 0) {
      if (state.isPriceRatioForward)
        return EthereumService.formatDouble((a / b).toString(), 5);
      return EthereumService.formatDouble((b / a).toString(), 5);
    }
    return "0.0";
  }

  String getTokenAddress(Token token) {
    String tokenAddress;
    if (token.getTokenName() == "xdai") {
      tokenAddress = "0x0000000000000000000000000000000000000001";
    } else {
      StockAddress stockAddress = XDaiStockData.getStockAddress(token);
      if (state.mode == Mode.LONG) {
        tokenAddress = stockAddress.long;
      } else if (state.mode == Mode.SHORT) {
        tokenAddress = stockAddress.short;
      }
    }
    return tokenAddress;
  }

  fromTokenChanged(Token selectedToken) async {
    state.toToken = CurrencyData.xdai;
    state.fromToken = selectedToken;
    (state.fromToken as Stock).mode = Mode.LONG;
    state.fromFieldController.text = "";
    state.toFieldController.text = "";
    state.toValue = 0;

    if (checkMarketClosed(selectedToken, Mode.LONG)) {
      state.marketClosed = true;
      emit(XDaiSyntheticsLoadingState(state));
      emit(XDaiSyntheticsAssetSelectedState(state, fromToken: selectedToken, mode: Mode.LONG));
    } else {
      state.marketClosed = false;
      emit(XDaiSyntheticsAssetSelectedState(state,
          fromToken: selectedToken, mode: Mode.LONG, isInProgress: true));

      await getAllowances();
      (selectedToken as Stock).longBalance =
      await getTokenBalance(selectedToken);
      emit(XDaiSyntheticsLoadingState(state));
      emit(XDaiSyntheticsAssetSelectedState(state,
          fromToken: selectedToken, isInProgress: false));
    }
  }

  toTokenChanged(Token selectedToken) async {
    state.fromToken = CurrencyData.xdai;
    state.toToken = selectedToken;
    (state.toToken as Stock).mode = Mode.LONG;
    state.fromFieldController.text = "";
    state.toFieldController.text = "";
    state.toValue = 0;

    if (checkMarketClosed(selectedToken, Mode.LONG)) {
      state.marketClosed = true;
      emit(XDaiSyntheticsLoadingState(state));
      emit(XDaiSyntheticsAssetSelectedState(state, toToken: selectedToken, mode: Mode.LONG));
    } else {
      state.marketClosed = false;
      emit(XDaiSyntheticsAssetSelectedState(state,
          toToken: selectedToken, mode: Mode.LONG, isInProgress: true));

      await getAllowances();
      (selectedToken as Stock).longBalance =
      await getTokenBalance(selectedToken);
      emit(XDaiSyntheticsLoadingState(state));
      emit(XDaiSyntheticsAssetSelectedState(state,
          toToken: selectedToken, isInProgress: false));
    }
  }

  addListenerToFromField() {
    if (!state.fromFieldController.hasListeners) {
      state.fromFieldController.addListener(() {
        listenInput();
      });
    }
  }

  listenInput() async {
    if (state is XDaiSyntheticsSelectAssetState) {

    }
    else {
      String input = state.fromFieldController.text;
      if (input == null || input.isEmpty) {
        input = "0.0";
      }
      if (isBuy()) {
        if ((state.fromToken as CryptoCurrency).getAllowances() >=
            EthereumService.getWei(input, state.fromToken.getTokenName())) {
          state.inputController.add(input);
          emit(XDaiSyntheticsAssetSelectedState(state, approved: true));
        } else {
          state.inputController.add(input);
          emit(XDaiSyntheticsAssetSelectedState(state, approved: false));
        }
      } else {
        if ((state.fromToken as Stock).getAllowances() >=
            EthereumService.getWei(input, state.fromToken.getTokenName())) {
          state.inputController.add(input);
          emit(XDaiSyntheticsAssetSelectedState(state, approved: true));
        } else {
          state.inputController.add(input);
          emit(XDaiSyntheticsAssetSelectedState(state, approved: false));
        }
      }
    }
  }

  reverseSync() {
    Token a = state.fromToken;
    state.fromToken = state.toToken;
    state.toToken = a;
    state.fromFieldController.text = "";
    state.toFieldController.text = "";
    state.toValue = 0;
    getAllowances();
  }

  reversePriceRatio() {
    if (state is XDaiSyntheticsAssetSelectedState) {
      emit(XDaiSyntheticsAssetSelectedState(state,
          isPriceRatioForward: !state.isPriceRatioForward));
    }
  }

  Future<void> setMode(Mode mode) async {
    if (!state.isInProgress && state.toToken != null) {
      if (mode != state.mode) {
        state.toFieldController.text = "";
        // state.fromFieldController.text = "";
        state.toValue = 0;
        state.approved = false;
      }
      if (isBuy()) {
        (state.toToken as Stock).mode = mode;
      } else {
        (state.fromToken as Stock).mode = mode;
      }
      if (checkMarketClosed(isBuy() ? state.toToken : state.fromToken, mode)) {
        state.marketClosed = true;
        emit(XDaiSyntheticsAssetSelectedState(state, mode: mode));
      } else {
        state.marketClosed = false;
        emit(XDaiSyntheticsAssetSelectedState(state, mode: mode));
        await getAllowances();
        listenInput();
      }
    }
  }

  void closeToast() {
    if (state is XDaiSyntheticsTransactionPendingState)
      emit(XDaiSyntheticsTransactionPendingState(state, showingToast: false));
    else if (state is XDaiSyntheticsTransactionFinishedState)
      emit(XDaiSyntheticsTransactionFinishedState(state, showingToast: false));
  }

  Future approve() async {
    if (!state.isInProgress) {
      try {
        var res = await state.service.approve(getTokenAddress(state.fromToken));
        emit(XDaiSyntheticsTransactionPendingState(state,
            transactionStatus: TransactionStatus(
                "Approve ${state.fromToken.name}",
                Status.PENDING,
                "Transaction Pending", res)));
        Stream<TransactionReceipt> result =
        state.service.ethService.pollTransactionReceipt(res);
        result.listen((event) {
          state.approved = event.status;
          if (event.status) {
            state.approved = true;
            emit(XDaiSyntheticsTransactionFinishedState(state,
                transactionStatus: TransactionStatus(
                    "Approve ${state.fromToken.name}",
                    Status.SUCCESSFUL,
                    "Transaction Successful",
                    res)));
          } else {
            emit(XDaiSyntheticsTransactionFinishedState(state,
                transactionStatus: TransactionStatus(
                    "Approve ${state.fromToken.name}",
                    Status.FAILED,
                    "Transaction Failed",
                    res)));
          }
        });
      } on Exception catch (_) {
        state.approved = false;
        emit(XDaiSyntheticsTransactionFinishedState(state,
            transactionStatus: TransactionStatus(
                "Approve ${state.fromToken.name}",
                Status.FAILED,
                "Transaction Failed")));
      }
    }
  }

  Future sell() async {
    if (state.approved && !state.isInProgress) {
      emit(XDaiSyntheticsTransactionPendingState(state,
          transactionStatus: TransactionStatus(
              "Sell ${state.fromFieldController.text} ${state.fromToken
                  .getTokenName()}",
              Status.PENDING,
              "Transaction Pending")));
      String tokenAddress = getTokenAddress(state.fromToken);

      List<ContractInputData> oracles =
      await XDaiStockData.getContractInputData(tokenAddress, await state.service.ethService.ethClient.getBlockNumber());
      if (oracles.length >= 2) {
        try {
          //sort oracles on price and then on oracle number
          List arr = [];
          oracles.asMap().forEach((index, element) {
            arr.add([index, element.getPrice()]);
          });
          arr.sort((a, b) => a[1].compareTo(b[1]));

          List<ContractInputData> inputOracles;
          if (arr[0][0] < arr[1][0]) {
            inputOracles = [oracles[arr[0][0]], oracles[arr[1][0]]];
          } else {
            inputOracles = [oracles[arr[1][0]], oracles[arr[0][0]]];
          }

          var res = await state.service
              .sell(tokenAddress, state.fromFieldController.text, inputOracles);
          emit(XDaiSyntheticsTransactionPendingState(state,
              transactionStatus: TransactionStatus(
                  "Sell ${state.fromFieldController.text} ${state.fromToken
                      .getTokenName()}",
                  Status.PENDING,
                  "Transaction Pending", res)));

          Stream<TransactionReceipt> result =
          state.service.ethService.pollTransactionReceipt(res);
          result.listen((event) async {
            if (event.status) {
              String fromBalance = await getTokenBalance(state.fromToken);
              String toBalance = await getTokenBalance(state.toToken);
              if (state.mode == Mode.LONG)
                (state.fromToken as Stock).longBalance = fromBalance;
              else
                (state.fromToken as Stock).shortBalance = fromBalance;

              (state.toToken as CryptoCurrency).balance = toBalance;
              emit(XDaiSyntheticsTransactionFinishedState(state,
                  transactionStatus: TransactionStatus(
                      "Sell ${state.fromFieldController.text} ${state.fromToken
                          .getTokenName()}",
                      Status.SUCCESSFUL,
                      "Transaction Successful",
                      res)));
            } else {
              emit(XDaiSyntheticsTransactionFinishedState(state,
                  transactionStatus: TransactionStatus(
                      "Sell ${state.fromFieldController.text} ${state.fromToken
                          .getTokenName()}",
                      Status.FAILED,
                      "Transaction Failed",
                      res)));
            }
          });
        } on Exception catch (_) {
          emit(XDaiSyntheticsTransactionFinishedState(state,
              transactionStatus: TransactionStatus(
                  "Sell ${state.fromFieldController.text} ${state.fromToken
                      .getTokenName()}",
                  Status.FAILED,
                  "Transaction Failed")));
        }
      } else {
        emit(XDaiSyntheticsTransactionFinishedState(state,
            transactionStatus: TransactionStatus(
                "oracles not available", Status.FAILED, "Transaction Failed")));
      }
    }
  }

  Future buy() async {
    if (!state.isInProgress) {
      emit(XDaiSyntheticsTransactionPendingState(state,
          transactionStatus: TransactionStatus(
              "Buy ${state.toFieldController.text} ${state.toToken
                  .getTokenName()}",
              Status.PENDING,
              "Transaction Pending")));
      String tokenAddress = getTokenAddress(state.toToken);
      List<ContractInputData> oracles =
      await XDaiStockData.getContractInputData(tokenAddress, await state.service.ethService.ethClient.getBlockNumber());
      if (oracles.length >= 2) {
        try {
          //sort oracles on price and then on oracle number
          List arr = [];
          oracles.asMap().forEach((index, element) {
            arr.add([index, element.getPrice()]);
          });
          arr.sort((a, b) => b[1].compareTo(a[1]));

          List<ContractInputData> inputOracles;
          if (arr[0][0] < arr[1][0]) {
            inputOracles = [oracles[arr[0][0]], oracles[arr[1][0]]];
          } else {
            inputOracles = [oracles[arr[1][0]], oracles[arr[0][0]]];
          }
          String maxPrice = arr[0][1].toString();
          var res = await state.service.buy(tokenAddress,
              state.toValue.toStringAsFixed(18), inputOracles, maxPrice);
          emit(XDaiSyntheticsTransactionPendingState(state,
              transactionStatus: TransactionStatus(
                  "Buy ${state.toFieldController.text} ${state.toToken
                      .getTokenName()}",
                  Status.PENDING,
                  "Transaction Pending", res)));
          Stream<TransactionReceipt> result =
          state.service.ethService.pollTransactionReceipt(res);
          result.listen((event) async {
            if (event.status) {
              String fromBalance = await getTokenBalance(state.fromToken);
              String toBalance = await getTokenBalance(state.toToken);
              if (state.mode == Mode.LONG)
                (state.toToken as Stock).longBalance = toBalance;
              else
                (state.toToken as Stock).shortBalance = toBalance;

              (state.fromToken as CryptoCurrency).balance = fromBalance;
              emit(XDaiSyntheticsTransactionFinishedState(state,
                  transactionStatus: TransactionStatus(
                      "Buy ${state.toFieldController.text} ${state.toToken
                          .getTokenName()}",
                      Status.SUCCESSFUL,
                      "Transaction Successful",
                      res)));
            } else {
              emit(XDaiSyntheticsTransactionFinishedState(state,
                  transactionStatus: TransactionStatus(
                      "Buy ${state.toFieldController.text} ${state.toToken
                          .getTokenName()}",
                      Status.FAILED,
                      "Transaction Failed",
                      res)));
            }
          });
        } on Exception catch (_) {
          emit(XDaiSyntheticsTransactionFinishedState(state,
              transactionStatus: TransactionStatus(
                  "Buy ${state.toFieldController.text} ${state.toToken
                      .getTokenName()}",
                  Status.FAILED,
                  "Transaction Failed")));
        }
      } else {
        emit(XDaiSyntheticsTransactionFinishedState(state,
            transactionStatus: TransactionStatus(
                "oracles not available", Status.FAILED, "Transaction Failed")));
      }
    }
  }

  void dispose() {
    state.timer?.cancel();
  }

  void getPrices() async {
    state.prices = await XDaiStockData.getPrices();
    // listenInput();
  }

  bool checkMarketClosed(Token selectedToken, Mode mode) {
    if (state.prices != null) {
      if (mode == Mode.LONG) {
        if (state.prices[selectedToken.getTokenName()].long.isClosed != null &&
            state.prices[selectedToken.getTokenName()].long.isClosed)
          return true;
        if (state.prices[selectedToken.getTokenName()].long.price == 0)
          return true;
        return false;
      }
      else {
        if (state.prices[selectedToken.getTokenName()].short.isClosed != null &&
            state.prices[selectedToken.getTokenName()].short.isClosed)
          return true;
        if (state.prices[selectedToken.getTokenName()].short.price == 0)
          return true;
        return false;
      }
      // return state.prices[selectedToken.getTokenName()].short.isClosed ??
      //     false;
    }
    return true;
  }

  double computeToPrice(String s) {
    double res;
    if (isBuy()) {
      if (state.mode == Mode.LONG)
        res = double.tryParse(s) /
            state.prices[state.toToken.getTokenName()].long.price;
      else
        res = double.tryParse(s) /
            state.prices[state.toToken.getTokenName()].short.price;
    } else {
      if (state.mode == Mode.LONG)
        res = double.tryParse(s) *
            state.prices[state.fromToken.getTokenName()].long.price;
      else
        res = double.tryParse(s) *
            state.prices[state.fromToken.getTokenName()].short.price;
    }
    return res;
  }

  Future<String> getRemCap() async {
    return await state.service.getUsedCap();
  }

  bool isBuy() => state.fromToken.getTokenName() == "xdai";

  bool checkMarketStatus() {
    List closedDays = ['Sat', 'Sun'];
    var f = DateFormat('EEE,HH,mm');
    var date = f.format(getNYC());
    List arr = date.split(',');
    if (closedDays.contains(arr[0]))
      return true;
    if ((int.parse(arr[1]) == 6 && int.parse(arr[2]) > 30 &&
        int.parse(arr[1]) < 20) ||
        (int.parse(arr[1]) > 6 && int.parse(arr[1]) < 20))
      return false;
    return true;
  }

  DateTime getNYC() {
    return DateTime.now().toUtc().subtract(Duration(hours: 4));
  }

  marketTimerFinished() {
    // init();
  }
}
