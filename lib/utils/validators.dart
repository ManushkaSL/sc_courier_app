class Validators {
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }

    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }

    return null;
  }

  static String? validatePasswordMatch(String? value, String? compareValue) {
    if (value != compareValue) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }

    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }

    return null;
  }

  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    // Sri Lankan phone number format: 07X XXXXXX or +947X XXXXXX
    final phoneRegex = RegExp(r'^(\+94|0)[0-9]{9}$');

    if (!phoneRegex.hasMatch(value.replaceAll(' ', ''))) {
      return 'Please enter a valid phone number';
    }

    return null;
  }

  static String? validateNIC(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'NIC number is required';
    }

    // Old format: 9 digits + V, New format: 12 digits
    final nicRegex = RegExp(r'^([0-9]{9}[Vv]|[0-9]{12})$');

    if (!nicRegex.hasMatch(value.replaceAll(' ', ''))) {
      return 'Please enter a valid NIC number';
    }

    return null;
  }

  static String? validateVehicleNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vehicle number is required';
    }

    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
}
