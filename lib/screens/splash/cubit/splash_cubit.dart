import 'package:bloc/bloc.dart';
import 'package:deus_mobile/data_source/stock_data.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../locator.dart';
import '../../../provider_service.dart';

part 'splash_state.dart';

class SplashCubit extends Cubit<SplashState> {
  SplashCubit() : super(SplashInitial());

  /// Reads the data from the phone (keys etc.) and fetches data from the server.
  Future<bool> initializeData() async {
    // if the data has already been fetched, skip this method.
    if (state is SplashSuccess) return true;

    emit(SplashLoading());

    /// get data from device
    try {
      debugPrint("Creating providers...");
      await locator<OmniServices>().createOmniServices();
      debugPrint("Created providers.");
    } catch (e) {
      emit(SplashError());
      return false;
    }

    emit(SplashSuccess());
    return true;
  }
}
